import AVFoundation
import MediaPlayer
import MediaToolbox
import SwiftUI
import UIKit
import OSLog
import Network

@MainActor final class PlaybackConnection {
    static let shared = PlaybackConnection()
    private let monitor = NWPathMonitor()
    private(set) var isUnmetered = false
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let allowed = path.status == .satisfied && !path.isExpensive && !path.isConstrained
            Task { @MainActor in self?.isUnmetered = allowed }
        }
        monitor.start(queue: DispatchQueue(label: "com.klymusic.connection"))
    }
}

@MainActor final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

struct LyricsCacheEntry: Codable {
    static let currentResolverVersion = 1
    var response: LyricsResponse
    var fetchedAt: Date
    var resolverVersion = LyricsCacheEntry.currentResolverVersion

    static func decode(_ data: Data) -> LyricsCacheEntry? {
        let decoder = JSONDecoder()
        if let entry = try? decoder.decode(Self.self, from: data), entry.response.hasContent { return entry }
        // Downloads and earlier releases saved the response without freshness metadata.
        guard let response = try? decoder.decode(LyricsResponse.self, from: data), response.hasContent else { return nil }
        return Self(response: response, fetchedAt: .distantPast, resolverVersion: 0)
    }

    func needsRefresh(at date: Date = .now) -> Bool {
        guard resolverVersion == Self.currentResolverVersion, response.hasContent else { return true }
        let lifetime: TimeInterval
        if !response.lines.isEmpty { lifetime = 7 * 24 * 60 * 60 }
        else if !(response.plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lifetime = 24 * 60 * 60 }
        else { lifetime = 6 * 60 * 60 }
        let age = date.timeIntervalSince(fetchedAt)
        return age < 0 || age >= lifetime
    }
}

enum AppNavigationTarget: Identifiable, Hashable {
    case artist(id: String, name: String)
    case album(MusicCollection)
    case query(title: String, query: String)

    var id: String {
        switch self {
        case .artist(let id, let name): return "artist|\(id)|\(name)"
        case .album(let c): return "album|\(c.id)"
        case .query(let t, let q): return "query|\(t)|\(q)"
        }
    }
}

enum AudioEQPreset: String, CaseIterable, Identifiable {
    case off, acoustic, bassBooster, bassReducer, classical, dance, lateNight, pop, rnb, rock, vocalBooster
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Kapalı"
        case .acoustic: return "Akustik"
        case .bassBooster: return "Bas Güçlendirici"
        case .bassReducer: return "Bas Azaltıcı"
        case .classical: return "Klasik"
        case .dance: return "Dans"
        case .lateNight: return "Gece Modu"
        case .pop: return "Pop"
        case .rnb: return "R&B ve Hip-Hop"
        case .rock: return "Rock"
        case .vocalBooster: return "Vokal Güçlendirici"
        }
    }
    var gainsDB: (low: Float, mid: Float, high: Float) {
        switch self {
        case .off: return (0, 0, 0)
        case .acoustic: return (2.5, 1.5, 3.0)
        case .bassBooster: return (6.0, -0.5, 0.5)
        case .bassReducer: return (-5.0, 0.5, 1.5)
        case .classical: return (1.5, 1.0, 2.5)
        case .dance: return (4.5, 0.5, 3.5)
        case .lateNight: return (-1.0, 3.0, -2.0)
        case .pop: return (1.5, 2.5, 2.0)
        case .rnb: return (5.0, 0.5, 2.0)
        case .rock: return (3.5, 1.5, 3.5)
        case .vocalBooster: return (-2.0, 4.5, 1.5)
        }
    }
    var preampGain: Float {
        switch self {
        case .off: return 1.0
        case .bassBooster, .rnb, .dance: return 0.84
        case .rock, .vocalBooster, .acoustic: return 0.88
        case .pop, .classical: return 0.92
        case .lateNight: return 0.86
        case .bassReducer: return 0.96
        }
    }
}

struct BiquadEQFilter {
    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var z1: Float = 0, z2: Float = 0

    init(centerHz: Float, sampleRate: Float, q: Float, gainDB: Float) {
        let a = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * centerHz / max(8000, sampleRate)
        let alpha = sinf(w0) / (2 * max(0.25, q))
        let norm = 1 + alpha / a
        b0 = (1 + alpha * a) / norm
        b1 = (-2 * cosf(w0)) / norm
        b2 = (1 - alpha * a) / norm
        a1 = b1
        a2 = (1 - alpha / a) / norm
    }

    private init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    static func lowPass(cutoffHz: Float, sampleRate: Float, q: Float = 0.707) -> BiquadEQFilter {
        let w0 = 2 * Float.pi * cutoffHz / max(8000, sampleRate)
        let cosW0 = cosf(w0)
        let alpha = sinf(w0) / (2 * max(0.25, q))
        let norm = 1 + alpha
        return BiquadEQFilter(
            b0: ((1 - cosW0) * 0.5) / norm,
            b1: (1 - cosW0) / norm,
            b2: ((1 - cosW0) * 0.5) / norm,
            a1: (-2 * cosW0) / norm,
            a2: (1 - alpha) / norm
        )
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

final class AudioRealtimeDSPState: @unchecked Sendable {
    static let shared = AudioRealtimeDSPState()
    private let lock = NSLock()
    private var _eqPreset: AudioEQPreset = AudioEQPreset(rawValue: UserDefaults.standard.string(forKey: "eqPreset") ?? "off") ?? .off
    private var _singEnabled = false
    private var _singVocalLevel: Float = 0.22

    struct Snapshot {
        let eqPreset: AudioEQPreset
        let singEnabled: Bool
        let singVocalLevel: Float
    }

    func update(eqPreset: AudioEQPreset? = nil, singEnabled: Bool? = nil, singVocalLevel: Float? = nil) {
        lock.lock()
        if let eqPreset { _eqPreset = eqPreset }
        if let singEnabled { _singEnabled = singEnabled }
        if let singVocalLevel { _singVocalLevel = min(1.0, max(0.0, singVocalLevel)) }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let value = Snapshot(eqPreset: _eqPreset, singEnabled: _singEnabled, singVocalLevel: _singVocalLevel)
        lock.unlock()
        return value
    }
}

private final class AudioTapContext {
    var sampleRate: Float = 44100
    var isFloatPCM = false
    var isNonInterleaved = true
    var channels: Int = 2
    private var configuredPreset: AudioEQPreset = .off
    private var lowL = BiquadEQFilter(centerHz: 95, sampleRate: 44100, q: 0.8, gainDB: 0)
    private var midL = BiquadEQFilter(centerHz: 1100, sampleRate: 44100, q: 0.9, gainDB: 0)
    private var highL = BiquadEQFilter(centerHz: 7500, sampleRate: 44100, q: 0.8, gainDB: 0)
    private var lowR = BiquadEQFilter(centerHz: 95, sampleRate: 44100, q: 0.8, gainDB: 0)
    private var midR = BiquadEQFilter(centerHz: 1100, sampleRate: 44100, q: 0.9, gainDB: 0)
    private var highR = BiquadEQFilter(centerHz: 7500, sampleRate: 44100, q: 0.8, gainDB: 0)
    private var singBassL = BiquadEQFilter.lowPass(cutoffHz: 160, sampleRate: 44100)
    private var singBassR = BiquadEQFilter.lowPass(cutoffHz: 160, sampleRate: 44100)

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = max(8000, Float(format.mSampleRate))
        channels = max(1, Int(format.mChannelsPerFrame))
        isFloatPCM = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && format.mBitsPerChannel == 32
        isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        rebuildFilters(for: AudioRealtimeDSPState.shared.snapshot().eqPreset)
        singBassL = BiquadEQFilter.lowPass(cutoffHz: 160, sampleRate: sampleRate)
        singBassR = BiquadEQFilter.lowPass(cutoffHz: 160, sampleRate: sampleRate)
    }

    private func rebuildFilters(for preset: AudioEQPreset) {
        configuredPreset = preset
        let bands = preset.bandGainsDB
        lowL = BiquadEQFilter(centerHz: 95, sampleRate: sampleRate, q: 0.8, gainDB: Float(bands.low))
        midL = BiquadEQFilter(centerHz: 1100, sampleRate: sampleRate, q: 0.9, gainDB: Float(bands.mid))
        highL = BiquadEQFilter(centerHz: 7500, sampleRate: sampleRate, q: 0.8, gainDB: Float(bands.high))
        lowR = BiquadEQFilter(centerHz: 95, sampleRate: sampleRate, q: 0.8, gainDB: Float(bands.low))
        midR = BiquadEQFilter(centerHz: 1100, sampleRate: sampleRate, q: 0.9, gainDB: Float(bands.mid))
        highR = BiquadEQFilter(centerHz: 7500, sampleRate: sampleRate, q: 0.8, gainDB: Float(bands.high))
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard isFloatPCM, frameCount > 0 else { return }
        let snap = AudioRealtimeDSPState.shared.snapshot()
        guard snap.eqPreset != .off || snap.singEnabled else { return }
        if snap.eqPreset != configuredPreset { rebuildFilters(for: snap.eqPreset) }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

        if isNonInterleaved && buffers.count >= 2,
           let ptrL = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let ptrR = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<frameCount {
                var l = ptrL[i]
                var r = ptrR[i]
                if snap.singEnabled {
                    let bassL = singBassL.process(l)
                    let bassR = singBassR.process(r)
                    let hiL = l - bassL
                    let hiR = r - bassR
                    let mid = 0.5 * (hiL + hiR)
                    let side = 0.5 * (hiL - hiR)
                    l = bassL + side + snap.singVocalLevel * mid
                    r = bassR - side + snap.singVocalLevel * mid
                }
                if snap.eqPreset != .off {
                    l = highL.process(midL.process(lowL.process(l)))
                    r = highR.process(midR.process(lowR.process(r)))
                }
                ptrL[i] = min(0.99, max(-0.99, l))
                ptrR[i] = min(0.99, max(-0.99, r))
            }
        } else if !isNonInterleaved, let ptr = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
            if channels >= 2 {
                for i in 0..<frameCount {
                    let base = i * channels
                    var l = ptr[base]
                    var r = ptr[base + 1]
                    if snap.singEnabled {
                        let bassL = singBassL.process(l)
                        let bassR = singBassR.process(r)
                        let hiL = l - bassL
                        let hiR = r - bassR
                        let mid = 0.5 * (hiL + hiR)
                        let side = 0.5 * (hiL - hiR)
                        l = bassL + side + snap.singVocalLevel * mid
                        r = bassR - side + snap.singVocalLevel * mid
                    }
                    if snap.eqPreset != .off {
                        l = highL.process(midL.process(lowL.process(l)))
                        r = highR.process(midR.process(lowR.process(r)))
                    }
                    ptr[base] = min(0.99, max(-0.99, l))
                    ptr[base + 1] = min(0.99, max(-0.99, r))
                }
            } else if snap.eqPreset != .off {
                for i in 0..<frameCount {
                    let s = highL.process(midL.process(lowL.process(ptr[i])))
                    ptr[i] = min(0.99, max(-0.99, s))
                }
            }
        }
    }
}

enum AudioTapEngine {
    @MainActor static func attachIfPossible(to item: AVPlayerItem) async {
        guard item.audioMix == nil else { return }
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
        let context = AudioTapContext()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<AudioTapContext>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                let ctx = Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                ctx.prepare(format: processingFormat.pointee)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut) == noErr else {
                    return
                }
                let frames = Int(numberFramesOut.pointee)
                guard frames > 0 else { return }
                let ctx = Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                ctx.process(bufferList: bufferListInOut, frameCount: frames)
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<AudioTapContext>.fromOpaque(callbacks.clientInfo!).release()
            return
        }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        if item.audioMix == nil { item.audioMix = mix }
    }
}

enum AudioLevelProcessor {
    static func targetVolume(for track: Track?, bitrate: Int, soundCheck: Bool, eqPreset: AudioEQPreset) -> Float {
        var gain: Float = eqPreset.preampGain
        if soundCheck {
            let text = ((track?.title ?? "") + " " + (track?.album ?? "")).lowercased()
            let gentle = text.contains("acoustic") || text.contains("akustik") || text.contains("pian") || text.contains("classical") || text.contains("chill")
            let reference: Float = gentle ? 0.94 : (bitrate >= 192 ? 0.84 : 0.86)
            gain *= reference
        }
        return min(1.0, max(0.58, gain))
    }
}

@MainActor final class MusicPlayer: ObservableObject {
    enum RepeatMode: String, CaseIterable { case off, all, one }
    @Published var current: Track?
    @Published var isPresented = false
    @Published var pendingTrack: Track?
    @Published var isPlaying = false
    @Published var isBuffering = false
    let clock = PlaybackClock()
    var position: Double { get { clock.position } set { clock.position = newValue } }
    var duration: Double { get { clock.duration } set { clock.duration = newValue } }
    @Published var queue: [Track] = []
    @Published var index = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var provider = ""
    @Published var bitrate = 0
    @Published var error: String?
    @Published var lyrics: LyricsResponse?
    @Published var lyricsLoading = false
    @Published var lyricsError: String?
    @Published var sleepUntil: Date?
    @Published var sleepAtEnd = false
    @Published var lastTransitionMS: Double = 0
    @Published var activeStationTitle: String? = nil
    @Published var isLiveStream = false
    @Published var requestedNavigation: AppNavigationTarget? = nil
    @Published var singModeEnabled = false {
        didSet { AudioRealtimeDSPState.shared.update(singEnabled: singModeEnabled) }
    }
    @Published var singVocalLevel: Double = 0.22 {
        didSet { AudioRealtimeDSPState.shared.update(singVocalLevel: Float(singVocalLevel)) }
    }
    @Published var sleepRemainingSeconds: Int? = nil
    weak var library: LibraryStore?
    let engine = AVQueuePlayer()
    private let tailPlayer = AVPlayer()
    private var originalQueue: [Track] = []
    private var activeStationQuery: String? = nil
    private var stationReplenishTask: Task<Void, Never>? = nil
    private var autoplayReplenishTask: Task<Void, Never>? = nil
    private var autoplayAttemptedTrackID: String?
    private var nowPlayingArtwork: (id: String, artwork: MPMediaItemArtwork)?
    private var itemTracks: [ObjectIdentifier: (Track, PlaybackAsset?, URL?)] = [:]
    private var matchingTask: Task<Void, Never>?
    private var matchingIDs: [String] = []
    private var warmupTask: Task<Void, Never>?
    private var warmupIDs: [String] = []
    private var warmupGeneration = UUID()
    private var selectionTask: Task<Void, Never>?
    private var nextTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var lyricGeneration = UUID()
    private var lyricsTrackID: String?
    private var lyricCacheEntry: LyricsCacheEntry?
    private let lyricsLoader: (Track) async throws -> LyricsResponse
    private var observations: [NSKeyValueObservation] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private weak var synchronizedItem: AVPlayerItem?
    private var bufferingTask: Task<Void, Never>?
    private var crossfadingTrackID: String?
    private var crossfadeTask: Task<Void, Never>?
    private var radioWatchdogTask: Task<Void, Never>?
    private var pendingResumePosition: (id: String, seconds: Double)?
    private var periodic: Any?
    private var notifications: [NSObjectProtocol] = []
    private var generation = UUID()
    private var resumeAfterInterruption = false
    private var manualSwitch = false
    private var switchStarted: CFAbsoluteTime = 0
    private var sleepEndItem: AVPlayerItem?
    private let logger = Logger(subsystem: "com.klymusic.app", category: "Playback")

    init(lyricsLoader: @escaping (Track) async throws -> LyricsResponse = { try await API.shared.lyrics($0) }) {
        self.lyricsLoader = lyricsLoader
        // Start when the first audio buffer is ready; do not wait for a speculative
        // long buffer on YouTube's progressively served AAC files.
        engine.automaticallyWaitsToMinimizeStalling = false
        observations.append(engine.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.bufferingTask?.cancel()
                if self.isBuffering {
                    let waitingItem = player.currentItem
                    self.bufferingTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(25)); try Task.checkCancellation() } catch { return }
                        guard let self, self.engine.currentItem === waitingItem, self.isBuffering else { return }
                        self.engine.pause(); self.error = L("Bu şarkı şu anda çalınamıyor. Yeniden dene.")
                    }
                }
                if self.isPlaying, self.switchStarted > 0 {
                    self.lastTransitionMS = (CFAbsoluteTimeGetCurrent() - self.switchStarted) * 1000
                    self.logger.info("transition_ms=\(self.lastTransitionMS) source=\(self.provider)")
                    self.switchStarted = 0
                }
                self.updateNowPlaying()
            }
        })
        observations.append(engine.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            let observedItem = player.currentItem
            Task { @MainActor in
                guard let self, self.engine.currentItem === observedItem else { return }
                self.itemChanged(observedItem)
            }
        })
        periodic = engine.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let liveItem = self.engine.currentItem else { return }
                self.itemChanged(liveItem)
                // Read after the actor hop: a callback may have been queued by the preceding song.
                let time = liveItem.currentTime().seconds
                let nextPosition = self.isLiveStream ? 0 : (time.isFinite ? min(max(0, time), max(0, self.duration)) : 0)
                if !self.isLiveStream, abs(self.position - nextPosition) > 0.03 { self.position = nextPosition }
                if self.isPlaying, !self.isLiveStream, let current = self.current, Int(nextPosition) % 5 == 0 {
                    UserDefaults.standard.set(current.id, forKey: "resumeTrackID")
                    UserDefaults.standard.set(nextPosition, forKey: "resumePosition")
                }
                let liveDuration = self.isLiveStream ? 0 : Self.playbackDuration(liveItem)
                if !self.isLiveStream, liveDuration > 0, abs(self.duration - liveDuration) > 0.1 { self.duration = liveDuration }
                if let until = self.sleepUntil {
                    let rem = until.timeIntervalSinceNow
                    if rem <= 0 {
                        self.engine.pause()
                        self.sleepUntil = nil
                        self.sleepRemainingSeconds = nil
                        self.applyAudioSettings()
                    } else {
                        let secs = Int(ceil(rem))
                        if self.sleepRemainingSeconds != secs { self.sleepRemainingSeconds = secs }
                        if rem <= 5.0 && self.crossfadeTask == nil {
                            let base = self.currentTargetVolume(for: self.current, bitrate: self.bitrate)
                            self.engine.volume = base * Float(max(0.05, rem / 5.0))
                        }
                    }
                } else if self.sleepRemainingSeconds != nil {
                    self.sleepRemainingSeconds = nil
                }
                if !self.isLiveStream,
                   self.isPlaying,
                   self.repeatMode != .one,
                   UserDefaults.standard.bool(forKey: "crossfadeEnabled"),
                   self.engine.items().count > 1,
                   let current = self.current,
                   self.crossfadingTrackID != current.id {
                    let configuredFade = UserDefaults.standard.object(forKey: "crossfadeSeconds") as? Double ?? 4.0
                    let fadeSeconds = min(12.0, max(1.0, configuredFade))
                    let effectiveDuration = self.duration > 0 ? self.duration : liveDuration
                    let remaining = effectiveDuration - nextPosition
                    if effectiveDuration > fadeSeconds + 4.0, remaining <= fadeSeconds, remaining > 0.5 {
                        self.crossfadingTrackID = current.id
                        let outgoingURL = self.itemTracks[ObjectIdentifier(liveItem)]?.2
                        self.performCrossfade(duration: min(fadeSeconds, remaining), outgoingURL: outgoingURL, outgoingTime: nextPosition)
                    }
                }
            }
        }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            let ended = note.object as? AVPlayerItem
            Task { @MainActor in
                guard let self, self.sleepAtEnd, let ended, ended === self.sleepEndItem else { return }
                self.engine.pause(); self.sleepAtEnd = false; self.sleepEndItem = nil
            }
        })
        notifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let item = note.object as? AVPlayerItem, item === self.engine.currentItem else { return }
                self.error = L("Bu şarkı şu anda çalınamıyor. Yeniden dene.")
                self.isBuffering = false
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if value == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.isPlaying; self.engine.pause()
                } else if self.resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.engine.play()
                }
            }
        })
        notifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.engine.pause() } }
        })
        configureCommands()
    }

    deinit {
        crossfadeTask?.cancel()
        radioWatchdogTask?.cancel()
        for obs in observations { obs.invalidate() }
        if let periodic { engine.removeTimeObserver(periodic) }
        for note in notifications { NotificationCenter.default.removeObserver(note) }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }
    private func asset(_ track: Track, source: String = "auto") async throws -> PlaybackAsset {
        try Task.checkCancellation()
        let quality = PlaybackPreferences.quality()
        let asset = try await API.shared.resolve(track, provider: source, quality: quality)
        try Task.checkCancellation()
        return asset
    }
    private func prepare(_ track: Track, source: String = "auto") async throws -> AVPlayerItem {
        try Task.checkCancellation()
        let item: AVPlayerItem
        var stream: PlaybackAsset?
        var mediaURL: URL?
        var playbackTrack = track
        if let url = library?.localURL(track.id), source == "auto" {
            let expected = track.duration > 0 ? track.duration : library?.saved.first(where: { $0.id == track.id })?.track?.duration ?? 0
            let local = AVURLAsset(url: url)
            let actual = try await local.load(.duration).seconds
            try Task.checkCancellation()
            if track.id.hasPrefix("local:") {
                guard actual.isFinite, actual > 0 else {
                    throw APIError.server(L("Bu ses dosyası okunamıyor."))
                }
            } else {
                guard expected > 0 else {
                    throw APIError.server(L("Bu indirmenin parça bilgisi eski. Şarkıyı silip yeniden indir."))
                }
                guard NativeCatalog.durationCompatible(expected: expected, actual: actual) else {
                    throw APIError.server(L("İndirilen dosya bu şarkıyla eşleşmiyor. Şarkıyı silip yeniden indir."))
                }
            }
            playbackTrack.duration = actual
            mediaURL = url
            item = AVPlayerItem(asset: local)
        } else {
            stream = try await asset(track, source: source)
            try Task.checkCancellation()
            let url = try API.mediaURL(stream!)
            mediaURL = url
            item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = PlaybackPreferences.savesData() ? 22 : 45
            if let stream, stream.duration.isFinite, stream.duration > 0 {
                // The resolver has checked this single recording's actual media duration.
                item.forwardPlaybackEndTime = CMTime(seconds: stream.duration, preferredTimescale: 600)
                if playbackTrack.duration <= 0 { playbackTrack.duration = stream.duration }
            }
        }
        itemTracks[ObjectIdentifier(item)] = (playbackTrack, stream, mediaURL)
        return item
    }

    static func playbackDuration(_ item: AVPlayerItem) -> Double {
        let actual = item.duration.seconds
        let boundary = item.forwardPlaybackEndTime.seconds
        if boundary.isFinite, boundary > 0 {
            return actual.isFinite && actual > 0 ? min(actual, boundary) : boundary
        }
        return actual.isFinite && actual > 0 ? actual : 0
    }

    /// Warm only a small visible set; canceled screens release their own requests.
    func warm(_ tracks: [Track]) {
        let matchCandidates = Array(tracks.prefix(3))
        if matchingIDs != matchCandidates.map(\.id) {
            matchingTask?.cancel(); matchingIDs = matchCandidates.map(\.id)
            matchingTask = Task(priority: .utility) {
                do { try await Task.sleep(for: .milliseconds(200)); try Task.checkCancellation() } catch { return }
                await API.shared.prepareMatches(matchCandidates)
            }
        }
        guard PlaybackPreferences.browseWarmupAllowed(savesData: PlaybackPreferences.savesData(), unmetered: PlaybackConnection.shared.isUnmetered) else {
            warmupGeneration = UUID(); warmupTask?.cancel(); warmupTask = nil; warmupIDs = []
            return
        }
        var seen = Set<String>()
        let candidates = Array(tracks.filter {
            library?.localURL($0.id) == nil && $0.id != current?.id && $0.id != pendingTrack?.id && seen.insert($0.id).inserted
        }.prefix(1))
        let ids = candidates.map(\.id)
        guard ids != warmupIDs || warmupTask == nil else { return }
        warmupIDs = ids
        warmupGeneration = UUID(); let token = warmupGeneration
        warmupTask?.cancel()
        guard !candidates.isEmpty else { warmupTask = nil; return }
        warmupTask = Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for track in candidates {
                    group.addTask { [weak self] in
                        guard !Task.isCancelled else { return }
                        _ = try? await self?.asset(track)
                    }
                }
            }
            if warmupGeneration == token { warmupTask = nil; warmupIDs = [] }
        }
    }

    func startStation(title: String, query: String, seedTracks: [Track]) {
        guard let first = seedTracks.first else { return }
        stationReplenishTask?.cancel()
        stationReplenishTask = nil
        activeStationTitle = title
        activeStationQuery = query
        startPlayback(first, in: seedTracks, source: "auto", keepStation: true)
    }

    func play(_ track: Track, in tracks: [Track]? = nil, source: String = "auto") {
        startPlayback(track, in: tracks, source: source, keepStation: tracks == nil)
    }

    private func startPlayback(_ track: Track, in tracks: [Track]? = nil, source: String = "auto", keepStation: Bool) {
        stopCrossfade()
        radioWatchdogTask?.cancel()
        radioWatchdogTask = nil
        isLiveStream = false
        pendingResumePosition = nil
        crossfadingTrackID = nil
        if !keepStation {
            stationReplenishTask?.cancel()
            stationReplenishTask = nil
            activeStationTitle = nil
            activeStationQuery = nil
        }
        autoplayReplenishTask?.cancel()
        autoplayReplenishTask = nil
        autoplayAttemptedTrackID = nil
        selectionTask?.cancel(); nextTask?.cancel()
        generation = UUID(); let token = generation
        if let tracks {
            originalQueue = tracks
            queue = shuffle ? [track] + tracks.filter { $0.id != track.id }.shuffled() : tracks
        } else if !queue.contains(where: { $0.id == track.id }) { queue = [track]; originalQueue = queue }
        index = queue.firstIndex { $0.id == track.id } ?? 0
        pendingTrack = track; error = nil
        switchStarted = CFAbsoluteTimeGetCurrent()
        // An already queued next item can start without resolving or rebuilding it.
        if source == "auto", let next = engine.items().dropFirst().first,
           itemTracks[ObjectIdentifier(next)]?.0.id == track.id {
            pendingTrack = nil; engine.advanceToNextItem(); itemChanged(engine.currentItem); engine.play(); return
        }
        selectionTask = Task(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let item = try await prepare(track, source: source)
                try Task.checkCancellation()
                guard generation == token else { return }
                try activateSession()
                manualSwitch = true
                engine.removeAllItems()
                itemTracks = [ObjectIdentifier(item): itemTracks[ObjectIdentifier(item)]!]
                engine.insert(item, after: nil)
                manualSwitch = false
                itemChanged(item)
                engine.play()
                pendingTrack = nil
            } catch is CancellationError { }
            catch {
                guard generation == token else { return }
                self.error = error.localizedDescription; pendingTrack = nil; switchStarted = 0
            }
        }
    }

    private func itemChanged(_ item: AVPlayerItem?) {
        guard !manualSwitch else { return }
        guard item === engine.currentItem else { return }
        guard let item else {
            synchronizedItem = nil
            itemStatusObservation = nil
            isPlaying = false; isBuffering = false
            updateNowPlaying()
            return
        }
        guard synchronizedItem !== item else { return }
        guard let (track, stream, _) = itemTracks[ObjectIdentifier(item)] else { return }
        synchronizedItem = item
        let liveItems = Set(engine.items().map(ObjectIdentifier.init))
        itemTracks = itemTracks.filter { liveItems.contains($0.key) }
        let trackChanged = current?.id != track.id
        current = track; position = 0; duration = stream?.duration ?? track.duration
        index = queue.firstIndex { $0.id == track.id } ?? index
        provider = isLiveStream ? "live" : (stream?.provider ?? "offline"); bitrate = stream?.bitrate ?? 0
        if crossfadeTask == nil {
            engine.volume = currentTargetVolume(for: track, bitrate: bitrate)
        }
        if !isLiveStream {
            Task { await AudioTapEngine.attachIfPossible(to: item) }
        }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor in
                guard let self, self.engine.currentItem === observed, observed.status == .failed else { return }
                self.engine.pause(); self.isBuffering = false
                Task { await API.shared.invalidatePlayback() }
                self.error = L("Bu şarkı şu anda çalınamıyor. Yeniden dene.")
            }
        }
        if trackChanged || nowPlayingArtwork?.id != track.id {
            nowPlayingArtwork = nil
        }
        if trackChanged {
            autoplayAttemptedTrackID = nil
            resetLyrics()
        }
        if UserDefaults.standard.object(forKey: "useListeningHistory") as? Bool ?? true {
            library?.played(track)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(track), forKey: "lastTrack")
        updateNowPlaying()
        Task {
            if let image = await ArtworkCache.shared.image(ArtworkRequest.sized(track.artworkURL, pixels: 640), fallback: track.artworkURL), current?.id == track.id {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.nowPlayingArtwork = (track.id, artwork)
                self.updateNowPlaying()
            }
        }
        prepareNext()
        replenishStationIfNeeded()
    }

    private func replenishStationIfNeeded() {
        guard let query = activeStationQuery, !query.isEmpty, queue.count - 1 - index <= 3 else { return }
        guard stationReplenishTask == nil else { return }
        let stationTitle = activeStationTitle
        let existingIDs = Set(queue.map(\.id))
        let existingIdentities = Set(queue.map(HomeFeed.identity))
        stationReplenishTask = Task(priority: .utility) { [weak self] in
            defer { Task { @MainActor in self?.stationReplenishTask = nil } }
            guard let response = try? await API.shared.search(query) else { return }
            try? Task.checkCancellation()
            await MainActor.run {
                guard let self, self.activeStationTitle == stationTitle, self.activeStationQuery == query else { return }
                let additions = response.tracks.filter {
                    !existingIDs.contains($0.id) && !existingIdentities.contains(HomeFeed.identity($0))
                }.prefix(10)
                guard !additions.isEmpty else { return }
                self.queue.append(contentsOf: additions)
                self.originalQueue.append(contentsOf: additions)
                if self.engine.items().count <= 1 { self.prepareNext() }
            }
        }
    }

    private func replenishAutoplayIfNeeded() {
        guard !CommandLine.arguments.contains("-serverURL"),
              UserDefaults.standard.object(forKey: "infiniteAutoplay") as? Bool ?? true,
              repeatMode == .off,
              activeStationQuery == nil,
              index + 1 >= queue.count,
              let seed = current,
              !seed.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              autoplayAttemptedTrackID != seed.id,
              autoplayReplenishTask == nil else { return }
        autoplayAttemptedTrackID = seed.id
        let token = generation
        let existingIDs = Set(queue.map(\.id))
        let existingIdentities = Set(queue.map(HomeFeed.identity))
        autoplayReplenishTask = Task(priority: .utility) { [weak self] in
            defer { Task { @MainActor in self?.autoplayReplenishTask = nil } }
            guard let response = try? await API.shared.search(seed.artist) else { return }
            try? Task.checkCancellation()
            await MainActor.run {
                guard let self,
                      self.generation == token,
                      self.repeatMode == .off,
                      self.activeStationQuery == nil,
                      self.current?.id == seed.id,
                      UserDefaults.standard.object(forKey: "infiniteAutoplay") as? Bool ?? true else { return }
                let additions = Array(response.tracks.filter {
                    !existingIDs.contains($0.id) && !existingIdentities.contains(HomeFeed.identity($0))
                }.prefix(8))
                guard !additions.isEmpty else { return }
                self.queue.append(contentsOf: additions)
                self.originalQueue.append(contentsOf: additions)
                if self.engine.items().count <= 1 { self.prepareNext() }
            }
        }
    }

    func prepareNext() {
        nextTask?.cancel()
        guard !queue.isEmpty, engine.currentItem != nil else { return }
        let nextIndex: Int
        if repeatMode == .one { nextIndex = index }
        else if index + 1 < queue.count { nextIndex = index + 1 }
        else if repeatMode == .all { nextIndex = 0 }
        else {
            replenishAutoplayIfNeeded()
            return
        }
        let next = queue[nextIndex]
        let token = generation
        if engine.items().count > 1 { return }
        nextTask = Task(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let item = try await prepare(next)
                try Task.checkCancellation()
                guard generation == token, engine.currentItem != nil, engine.items().count == 1 else { return }
                engine.insert(item, after: engine.currentItem)
                let second = nextIndex + 1
                if !PlaybackPreferences.savesData(), PlaybackConnection.shared.isUnmetered,
                   second < queue.count, library?.localURL(queue[second].id) == nil {
                    _ = try? await asset(queue[second])
                }
            } catch { /* Current playback continues; selecting Next exposes a useful error. */ }
        }
    }

    func refreshPreparation() {
        warmupGeneration = UUID(); warmupTask?.cancel(); warmupTask = nil; warmupIDs = []
        nextTask?.cancel()
        for item in engine.items().dropFirst() {
            engine.remove(item)
            itemTracks[ObjectIdentifier(item)] = nil
        }
        prepareNext()
    }

    func toggle() {
        stopCrossfade()
        if isPlaying { engine.pause() }
        else if engine.currentItem?.status == .failed, let current {
            Task {
                await API.shared.invalidatePlayback()
                if isLiveStream {
                    activeStationQuery = nil; isLiveStream = false
                }
                play(current)
            }
        }
        else if engine.currentItem != nil { try? activateSession(); engine.play() }
        else if let current {
            if let pending = pendingResumePosition, pending.id == current.id {
                pendingResumePosition = nil
                resume(current)
            } else {
                play(current)
            }
        }
    }
    func next() {
        stopCrossfade()
        guard !isLiveStream else { return }
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { play(queue[index + 1]) }
        else if repeatMode != .off { play(queue[0]) }
        else { engine.pause() }
    }
    func previous() {
        stopCrossfade()
        guard !isLiveStream else { return }
        if position > 3 { seek(0) }
        else if index > 0 { play(queue[index - 1]) }
        else { seek(0) }
    }
    func seek(_ seconds: Double) {
        stopCrossfade()
        guard !isLiveStream else { return }
        guard seconds.isFinite, duration.isFinite else { return }
        let target = min(max(0, seconds), max(0, duration))
        engine.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target; updateNowPlaying()
    }
    func applyAudioSettings() {
        let preset = AudioEQPreset(rawValue: UserDefaults.standard.string(forKey: "eqPreset") ?? "off") ?? .off
        AudioRealtimeDSPState.shared.update(eqPreset: preset)
        guard crossfadeTask == nil else { return }
        engine.volume = currentTargetVolume(for: current, bitrate: bitrate)
    }

    private func currentTargetVolume(for track: Track?, bitrate: Int) -> Float {
        let defaults = UserDefaults.standard
        let soundCheck = defaults.object(forKey: "soundCheckEnabled") as? Bool ?? true
        let preset = AudioEQPreset(rawValue: defaults.string(forKey: "eqPreset") ?? "off") ?? .off
        return AudioLevelProcessor.targetVolume(for: track, bitrate: bitrate, soundCheck: soundCheck, eqPreset: preset)
    }

    private func stopCrossfade() {
        crossfadeTask?.cancel()
        crossfadeTask = nil
        tailPlayer.pause()
        tailPlayer.replaceCurrentItem(with: nil)
    }

    private func performCrossfade(duration fadeDuration: Double, outgoingURL: URL?, outgoingTime: Double) {
        crossfadeTask?.cancel()
        guard engine.items().count > 1 else { return }
        let startGain = max(0.2, engine.volume)
        let nextTrack = engine.items().dropFirst().first.flatMap { itemTracks[ObjectIdentifier($0)]?.0 }
        let nextBitrate = engine.items().dropFirst().first.flatMap { itemTracks[ObjectIdentifier($0)]?.1?.bitrate ?? 0 } ?? 0
        let targetGain = currentTargetVolume(for: nextTrack, bitrate: nextBitrate)

        crossfadeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.tailPlayer.pause()
                self.tailPlayer.replaceCurrentItem(with: nil)
                self.crossfadeTask = nil
            }
            var tailReady = false
            if let outgoingURL {
                let tailItem = AVPlayerItem(url: outgoingURL)
                self.tailPlayer.volume = startGain
                self.tailPlayer.replaceCurrentItem(with: tailItem)
                await self.tailPlayer.seek(to: CMTime(seconds: max(0, outgoingTime), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                for _ in 0..<12 {
                    if Task.isCancelled { return }
                    if tailItem.status == .readyToPlay { tailReady = true; break }
                    if tailItem.status == .failed { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            if Task.isCancelled || self.engine.items().count <= 1 { return }
            if tailReady {
                self.tailPlayer.play()
                self.engine.volume = 0
                self.engine.advanceToNextItem()
                self.itemChanged(self.engine.currentItem)
                self.engine.play()
                let steps = 20
                let stepNanoseconds = UInt64((max(0.5, fadeDuration) / Double(steps)) * 1_000_000_000)
                for step in 1...steps {
                    if Task.isCancelled { return }
                    let t = Float(step) / Float(steps)
                    self.tailPlayer.volume = startGain * cosf(t * (.pi / 2))
                    self.engine.volume = targetGain * sinf(t * (.pi / 2))
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }
            } else {
                self.engine.volume = 0
                self.engine.advanceToNextItem()
                self.itemChanged(self.engine.currentItem)
                self.engine.play()
                let steps = 10
                for step in 1...steps {
                    if Task.isCancelled { return }
                    self.engine.volume = targetGain * (Float(step) / Float(steps))
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            self.engine.volume = targetGain
        }
    }

    func restoreLastSessionIfNeeded() {
        guard !CommandLine.arguments.contains("-serverURL"),
              current == nil,
              pendingTrack == nil,
              let data = UserDefaults.standard.data(forKey: "lastTrack"),
              let track = try? JSONDecoder().decode(Track.self, from: data) else { return }
        current = track
        queue = [track]
        originalQueue = [track]
        index = 0
        duration = track.duration.isFinite && track.duration > 0 ? track.duration : 0
        if UserDefaults.standard.string(forKey: "resumeTrackID") == track.id {
            let saved = UserDefaults.standard.double(forKey: "resumePosition")
            if saved.isFinite, saved > 0, (duration <= 0 || saved < duration - 3) {
                position = saved
                pendingResumePosition = (track.id, saved)
            }
        }
        updateNowPlaying()
    }

    func playLiveRadio(id: String, title: String, subtitle: String, streamURL: URL?, artwork: String?, fallbackQuery: String, fallbackSeeds: [Track] = []) {
        stopCrossfade()
        radioWatchdogTask?.cancel()
        radioWatchdogTask = nil
        selectionTask?.cancel()
        nextTask?.cancel()
        autoplayReplenishTask?.cancel()
        stationReplenishTask?.cancel()
        generation = UUID(); let token = generation

        guard !CommandLine.arguments.contains("-serverURL"),
              let streamURL, NativeCatalog.allowedLiveRadioURL(streamURL) else {
            Task { [weak self] in
                guard let self else { return }
                let tracks = !fallbackSeeds.isEmpty ? fallbackSeeds : ((try? await API.shared.search(fallbackQuery).tracks) ?? [])
                guard self.generation == token, !tracks.isEmpty else { return }
                self.startStation(title: title, query: fallbackQuery, seedTracks: tracks)
            }
            return
        }

        isLiveStream = true
        activeStationTitle = title
        activeStationQuery = fallbackQuery
        let liveTrack = Track(id: "live:" + id, title: title, artist: subtitle, album: L("CANLI İSTASYON"), duration: 0, artwork: artwork, source: "live")
        queue = [liveTrack]
        originalQueue = [liveTrack]
        index = 0
        current = liveTrack
        pendingTrack = liveTrack
        position = 0
        duration = 0
        error = nil
        switchStarted = CFAbsoluteTimeGetCurrent()

        do {
            try activateSession()
            let item = AVPlayerItem(url: streamURL)
            manualSwitch = true
            engine.removeAllItems()
            itemTracks = [ObjectIdentifier(item): (liveTrack, nil, streamURL)]
            engine.insert(item, after: nil)
            manualSwitch = false
            itemChanged(item)
            engine.volume = currentTargetVolume(for: liveTrack, bitrate: 128)
            engine.play()

            radioWatchdogTask = Task { [weak self] in
                for _ in 0..<70 {
                    if Task.isCancelled { return }
                    guard let self, self.generation == token else { return }
                    if self.engine.timeControlStatus == .playing {
                        self.pendingTrack = nil
                        self.error = nil
                        return
                    }
                    if item.status == .failed { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let self, self.generation == token, self.isLiveStream else { return }
                self.isLiveStream = false
                let tracks = !fallbackSeeds.isEmpty ? fallbackSeeds : ((try? await API.shared.search(fallbackQuery).tracks) ?? [])
                guard self.generation == token, !tracks.isEmpty else {
                    self.pendingTrack = nil
                    return
                }
                self.startStation(title: title, query: fallbackQuery, seedTracks: tracks)
            }
        } catch {
            isLiveStream = false
            pendingTrack = nil
            self.error = error.localizedDescription
        }
    }
    func toggleShuffle() {
        shuffle.toggle()
        if shuffle, let current { queue = [current] + queue.filter { $0.id != current.id }.shuffled(); index = 0 }
        else { queue = originalQueue; index = queue.firstIndex { $0.id == current?.id } ?? 0 }
        resetUpcoming()
    }
    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off
        resetUpcoming()
    }
    private var activeQueueIndex: Int? {
        guard let id = (pendingTrack ?? current)?.id else { return nil }
        return queue.firstIndex { $0.id == id }
    }

    /// The queue retains history for Previous; upcoming tracks exclude the current song.
    var historyTracks: [Track] {
        guard let activeQueueIndex, activeQueueIndex > 0 else { return [] }
        return Array(queue.prefix(activeQueueIndex))
    }

    var upcomingTracks: [Track] {
        Array(queue.dropFirst(activeQueueIndex.map { $0 + 1 } ?? 0))
    }

    func playFromHistory(id: String) {
        guard let track = historyTracks.first(where: { $0.id == id }) else { return }
        play(track)
    }

    func playUpcoming(id: String) {
        guard let track = upcomingTracks.first(where: { $0.id == id }) else { return }
        play(track) // Keep the existing queue and shuffle order.
    }

    func removeUpcoming(id: String) {
        guard upcomingTracks.contains(where: { $0.id == id }) else { return }
        queue.removeAll { $0.id == id }
        finishQueueEdit()
    }

    func moveUpcoming(from offsets: IndexSet, to destination: Int, snapshot: [Track]) {
        guard (0...snapshot.count).contains(destination) else { return }
        let liveIDs = Set(upcomingTracks.map(\.id))
        let moving = offsets.sorted().compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
            .filter { liveIDs.contains($0.id) }
        guard !moving.isEmpty else { return }
        let movedIDs = Set(moving.map(\.id))
        // Resolve by identity, not a stale list offset if playback advances during a drag.
        let anchor = snapshot.dropFirst(destination).first { liveIDs.contains($0.id) && !movedIDs.contains($0.id) }
        queue.removeAll { movedIDs.contains($0.id) }
        let insertion = anchor.flatMap { next in queue.firstIndex { $0.id == next.id } } ?? queue.endIndex
        queue.insert(contentsOf: moving, at: insertion)
        finishQueueEdit()
    }

    func clearUpcoming() {
        guard !upcomingTracks.isEmpty else { return }
        if let activeQueueIndex { queue = Array(queue.prefix(activeQueueIndex + 1)) }
        else { queue = [] }
        if repeatMode == .all { repeatMode = .off }
        autoplayAttemptedTrackID = current?.id
        finishQueueEdit()
    }

    private func finishQueueEdit() {
        index = activeQueueIndex ?? 0
        originalQueue = queue
        resetUpcoming()
    }
    private func resetUpcoming() {
        nextTask?.cancel()
        for item in engine.items().dropFirst() { engine.remove(item); itemTracks[ObjectIdentifier(item)] = nil }
        prepareNext()
    }
    func addToQueue(_ track: Track) {
        if queue.isEmpty { play(track, in: [track]); return }
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track); originalQueue = queue; prepareNext()
    }
    func playNext(_ track: Track) {
        guard current != nil else { play(track, in: [track]); return }
        guard current?.id != track.id else { return }
        queue.removeAll { $0.id == track.id }
        index = queue.firstIndex { $0.id == current?.id } ?? 0
        queue.insert(track, at: min(index + 1, queue.count))
        originalQueue = queue; resetUpcoming()
    }
    func resume(_ track: Track) {
        if current?.id == track.id, engine.currentItem != nil { if !isPlaying { toggle() }; return }
        let saved = UserDefaults.standard.string(forKey: "resumeTrackID") == track.id ? UserDefaults.standard.double(forKey: "resumePosition") : 0
        play(track, in: library?.recent ?? [track])
        let token = generation
        Task {
            await selectionTask?.value
            guard generation == token, current?.id == track.id else { return }
            if saved > 0 && saved < duration - 3 { seek(saved) }
        }
    }
    private func resetLyrics() {
        lyricTask?.cancel()
        lyricTask = nil
        lyricGeneration = UUID()
        lyricsTrackID = nil
        lyricCacheEntry = nil
        lyrics = nil
        lyricsLoading = false
        lyricsError = nil
    }
    func loadLyrics(force: Bool = false) {
        guard let track = current else { return }
        if lyricsTrackID != track.id { resetLyrics(); lyricsTrackID = track.id }
        guard force || lyricTask == nil else { return }
        if lyricCacheEntry == nil,
           let data = try? Data(contentsOf: MusicFiles.lyrics(track.id)),
           let saved = LyricsCacheEntry.decode(data) {
            lyricCacheEntry = saved
            lyrics = saved.response
        }
        if !force, let saved = lyricCacheEntry, !saved.needsRefresh() {
            lyrics = saved.response; lyricsLoading = false; lyricsError = nil
            return
        }
        lyricTask?.cancel()
        lyricGeneration = UUID(); let token = lyricGeneration
        // Keep offline words on screen while looking for newer, timed lyrics.
        lyricsLoading = lyrics?.hasContent != true; lyricsError = nil
        lyricTask = Task {
            defer {
                if lyricGeneration == token { lyricsLoading = false; lyricTask = nil }
            }
            do {
                let fetched = try await lyricsLoader(track)
                try Task.checkCancellation()
                guard current?.id == track.id, lyricGeneration == token, fetched.hasContent else { return }
                let response: LyricsResponse
                if let saved = lyricCacheEntry?.response, !saved.lines.isEmpty, fetched.lines.isEmpty {
                    response = saved
                } else { response = fetched }
                let entry = LyricsCacheEntry(response: response, fetchedAt: .now)
                lyrics = response
                lyricCacheEntry = entry
                if let data = try? JSONEncoder().encode(entry) {
                    try? data.write(to: MusicFiles.lyrics(track.id), options: .atomic)
                }
            } catch is CancellationError { }
            catch {
                guard current?.id == track.id, lyricGeneration == token else { return }
                if lyrics?.hasContent != true { lyricsError = L("Şarkı sözleri yüklenemedi.") }
            }
        }
    }
    func setSleep(minutes: Int?) {
        sleepAtEnd = false
        sleepEndItem = nil
        sleepUntil = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
        sleepRemainingSeconds = minutes.map { $0 * 60 }
        if minutes == nil { applyAudioSettings() }
    }
    func setSleepAtEnd() { sleepUntil = nil; sleepRemainingSeconds = nil; sleepEndItem = engine.currentItem; sleepAtEnd = sleepEndItem != nil; applyAudioSettings() }
    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            MPRemoteCommandCenter.shared().likeCommand.isActive = false
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: isLiveStream ? 0.0 : duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: isLiveStream ? 0.0 : position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(max(engine.rate, 1.0)) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
            MPNowPlayingInfoPropertyExternalContentIdentifier: track.id
        ]
        if let nowPlayingArtwork, nowPlayingArtwork.id == track.id {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork.artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        MPRemoteCommandCenter.shared().likeCommand.isActive = library?.isFavorite(track) ?? false
    }
    private func configureCommands() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in try? self?.activateSession(); self?.engine.play() }; return .success }
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.engine.pause() }; return .success }
        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.isEnabled = true
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.isEnabled = true
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.likeCommand.isEnabled = true
        commands.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let current = self.current else { return }
                self.library?.toggleFavorite(current)
                self.updateNowPlaying()
            }
            return .success
        }
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
}
