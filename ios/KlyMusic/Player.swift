import AVFoundation
import MediaPlayer
import SwiftUI
import OSLog

@MainActor final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
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
    weak var library: LibraryStore?
    let engine = AVQueuePlayer()
    private var originalQueue: [Track] = []
    private var itemTracks: [ObjectIdentifier: (Track, PlaybackAsset?)] = [:]
    private var warmupTask: Task<Void, Never>?
    private var warmupIDs: [String] = []
    private var warmupGeneration = UUID()
    private var selectionTask: Task<Void, Never>?
    private var nextTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var lyricGeneration = UUID()
    private var lyricsTrackID: String?
    private let lyricsLoader: (Track) async throws -> LyricsResponse
    private var observations: [NSKeyValueObservation] = []
    private var itemStatusObservation: NSKeyValueObservation?
    private weak var synchronizedItem: AVPlayerItem?
    private var bufferingTask: Task<Void, Never>?
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
                let nextPosition = time.isFinite ? min(max(0, time), max(0, self.duration)) : 0
                if abs(self.position - nextPosition) > 0.03 { self.position = nextPosition }
                if self.isPlaying, let current = self.current, Int(nextPosition) % 5 == 0 {
                    UserDefaults.standard.set(current.id, forKey: "resumeTrackID")
                    UserDefaults.standard.set(nextPosition, forKey: "resumePosition")
                }
                let liveDuration = Self.playbackDuration(liveItem)
                if liveDuration > 0, abs(self.duration - liveDuration) > 0.1 { self.duration = liveDuration }
                if let until = self.sleepUntil, until <= .now { self.engine.pause(); self.sleepUntil = nil }
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

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
    }
    private func asset(_ track: Track, source: String = "auto") async throws -> PlaybackAsset {
        try Task.checkCancellation()
        let quality = UserDefaults.standard.string(forKey: "quality") ?? "auto"
        let asset = try await API.shared.resolve(track, provider: source, quality: quality)
        try Task.checkCancellation()
        return asset
    }
    private func prepare(_ track: Track, source: String = "auto") async throws -> AVPlayerItem {
        try Task.checkCancellation()
        let item: AVPlayerItem
        var stream: PlaybackAsset?
        var playbackTrack = track
        if let url = library?.localURL(track.id), source == "auto" {
            let expected = track.duration > 0 ? track.duration : library?.saved.first(where: { $0.id == track.id })?.track?.duration ?? 0
            guard expected > 0 else {
                throw APIError.server(L("Bu indirmenin parça bilgisi eski. Şarkıyı silip yeniden indir."))
            }
            let local = AVURLAsset(url: url)
            let actual = try await local.load(.duration).seconds
            try Task.checkCancellation()
            guard NativeCatalog.durationCompatible(expected: expected, actual: actual) else {
                throw APIError.server(L("İndirilen dosya bu şarkıyla eşleşmiyor. Şarkıyı silip yeniden indir."))
            }
            playbackTrack.duration = actual
            item = AVPlayerItem(asset: local)
        } else {
            stream = try await asset(track, source: source)
            try Task.checkCancellation()
            let url = try API.mediaURL(stream!)
            item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 1
            if let stream, stream.duration.isFinite, stream.duration > 0 {
                // The resolver has checked this single recording's actual media duration.
                item.forwardPlaybackEndTime = CMTime(seconds: stream.duration, preferredTimescale: 600)
                if playbackTrack.duration <= 0 { playbackTrack.duration = stream.duration }
            }
        }
        itemTracks[ObjectIdentifier(item)] = (playbackTrack, stream)
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
        var seen = Set<String>()
        let candidates = Array(tracks.filter {
            library?.localURL($0.id) == nil && $0.id != current?.id && $0.id != pendingTrack?.id && seen.insert($0.id).inserted
        }.prefix(2))
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

    func play(_ track: Track, in tracks: [Track]? = nil, source: String = "auto") {
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
        selectionTask = Task {
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
        guard let (track, stream) = itemTracks[ObjectIdentifier(item)] else { return }
        synchronizedItem = item
        let liveItems = Set(engine.items().map(ObjectIdentifier.init))
        itemTracks = itemTracks.filter { liveItems.contains($0.key) }
        let trackChanged = current?.id != track.id
        current = track; position = 0; duration = stream?.duration ?? track.duration
        index = queue.firstIndex { $0.id == track.id } ?? index
        provider = stream?.provider ?? "offline"; bitrate = stream?.bitrate ?? 0
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor in
                guard let self, self.engine.currentItem === observed, observed.status == .failed else { return }
                self.engine.pause(); self.isBuffering = false
                Task { await API.shared.invalidatePlayback() }
                self.error = L("Bu şarkı şu anda çalınamıyor. Yeniden dene.")
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        library?.played(track)
        UserDefaults.standard.set(try? JSONEncoder().encode(track), forKey: "lastTrack")
        if trackChanged { resetLyrics() }
        updateNowPlaying()
        Task {
            if let image = await ArtworkCache.shared.image(track.artworkURL), current?.id == track.id {
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
        prepareNext()
    }

    func prepareNext() {
        nextTask?.cancel()
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if repeatMode == .one { nextIndex = index }
        else if index + 1 < queue.count { nextIndex = index + 1 }
        else if repeatMode == .all { nextIndex = 0 }
        else { return }
        let next = queue[nextIndex]
        let token = generation
        if engine.items().count > 1 { return }
        nextTask = Task {
            do {
                try Task.checkCancellation()
                let item = try await prepare(next)
                try Task.checkCancellation()
                guard generation == token, engine.currentItem != nil, engine.items().count == 1 else { return }
                engine.insert(item, after: engine.currentItem)
                let second = nextIndex + 1
                if second < queue.count, library?.localURL(queue[second].id) == nil {
                    _ = try? await asset(queue[second])
                }
            } catch { /* Current playback continues; selecting Next exposes a useful error. */ }
        }
    }

    func toggle() {
        if isPlaying { engine.pause() }
        else if engine.currentItem?.status == .failed, let current {
            Task {
                await API.shared.invalidatePlayback()
                play(current)
            }
        }
        else if engine.currentItem != nil { try? activateSession(); engine.play() }
        else if let current { play(current) }
    }
    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count { play(queue[index + 1]) }
        else if repeatMode != .off { play(queue[0]) }
        else { engine.pause() }
    }
    func previous() {
        if position > 3 { seek(0) }
        else if index > 0 { play(queue[index - 1]) }
        else { seek(0) }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite, duration.isFinite else { return }
        let target = min(max(0, seconds), max(0, duration))
        engine.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target; updateNowPlaying()
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
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
        index = queue.firstIndex { $0.id == current?.id } ?? 0
        originalQueue = queue; resetUpcoming()
    }
    func removeFromQueue(at offsets: IndexSet) {
        let protected = IndexSet(offsets.filter { queue[$0].id != current?.id })
        queue.remove(atOffsets: protected); originalQueue = queue
        index = queue.firstIndex { $0.id == current?.id } ?? 0; resetUpcoming()
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
        lyricGeneration = UUID()
        lyricsTrackID = nil
        lyrics = nil
        lyricsLoading = false
        lyricsError = nil
    }
    func loadLyrics(force: Bool = false) {
        guard let track = current else { return }
        if lyricsTrackID != track.id { resetLyrics(); lyricsTrackID = track.id }
        guard force || (lyrics == nil && !lyricsLoading) else { return }
        lyricTask?.cancel()
        lyricGeneration = UUID(); let token = lyricGeneration
        lyricsLoading = true; lyricsError = nil
        if force { lyrics = nil }
        lyricTask = Task {
            defer {
                if lyricGeneration == token { lyricsLoading = false }
            }
            if !force, let data = try? Data(contentsOf: MusicFiles.lyrics(track.id)),
               let saved = try? JSONDecoder().decode(LyricsResponse.self, from: data),
               saved.instrumental || !(saved.plain ?? "").isEmpty || !(saved.synced ?? "").isEmpty {
                if current?.id == track.id, lyricGeneration == token { lyrics = saved }; return
            }
            do {
                let fetched = try await lyricsLoader(track)
                try Task.checkCancellation()
                if current?.id == track.id, lyricGeneration == token {
                    lyrics = fetched
                    if fetched.instrumental || !(fetched.plain ?? "").isEmpty || !(fetched.synced ?? "").isEmpty,
                       let data = try? JSONEncoder().encode(fetched) {
                        try? data.write(to: MusicFiles.lyrics(track.id), options: .atomic)
                    }
                }
            } catch is CancellationError { }
            catch {
                guard current?.id == track.id, lyricGeneration == token else { return }
                lyricsError = L("Şarkı sözleri yüklenemedi. Yeniden dene.")
            }
        }
    }
    func setSleep(minutes: Int?) { sleepAtEnd = false; sleepEndItem = nil; sleepUntil = minutes.map { Date().addingTimeInterval(Double($0 * 60)) } }
    func setSleepAtEnd() { sleepUntil = nil; sleepEndItem = engine.currentItem; sleepAtEnd = sleepEndItem != nil }
    private func updateNowPlaying() {
        guard let track = current else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = engine.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func configureCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in try? self?.activateSession(); self?.engine.play() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.engine.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
}
