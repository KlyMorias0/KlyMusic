//
//  YouTube.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 04.09.21.
//

import Foundation
@preconcurrency import os.log

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
public class YouTube {
    /// Resolve only audio formats while retaining all client/fallback alternatives.
    public var audioOnly = false
    
    private var _js: String?
    private var _jsURL: URL?
    
    // NSCache is thread-safe. A mutable global URL/string pair can mix two
    // player versions when different songs resolve concurrently.
    private static let scriptCache: NSCache<NSURL, NSString> = {
        let cache = NSCache<NSURL, NSString>()
        cache.countLimit = 3
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    private static var scriptDiskDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YouTubePlayerJS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func scriptDiskURL(for url: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(url.path.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.suffix(72))
        return scriptDiskDirectory.appendingPathComponent(cleaned + ".js")
    }

    private static func trimDiskScripts() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scriptDiskDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > 3 else { return }
        let sorted = files.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in sorted.prefix(files.count - 2) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func clearScriptCaches() {
        scriptCache.removeAllObjects()
        if let files = try? FileManager.default.contentsOfDirectory(at: scriptDiskDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }
    
    private var _videoInfos: [InnerTube.VideoInfo]?
    
    private var _watchHTML: String?
    private var _embedHTML: String?
    private var playerConfigArgs: [String: Any]?
    private var _ageRestricted: Bool?
    private var _signatureTimestamp: Int?
    private var _ytcfg: Extraction.YtCfg?
    
    private var _fmtStreams: [Stream]?
    
    private var initialData: Data?

    /// Represents a property that provides metadata for a YouTube video.
    ///
    /// This property allows you to retrieve metadata for a YouTube video asynchronously.
    /// - Note: Currently doesn't respect `method` set. It always uses `.local`
    public var metadata: YouTubeMetadata? {
        get async throws {
            return .metadata(from: try await videoDetails)
        }
    }

    public let videoID: String
    
    var watchURL: URL {
        URL(string: "https://youtube.com/watch?v=\(videoID)")!
    }
    
    private var extendedWatchURL: URL {
        URL(string: "https://youtube.com/watch?v=\(videoID)&bpctr=9999999999&has_verified=1")!
    }
    
    var embedURL: URL {
        URL(string: "https://www.youtube.com/embed/\(videoID)")!
    }
    
    // stream monostate TODO
    
    private var author: String?
    private var title: String?
    private var publishDate: String?
    
    let useOAuth: Bool
    let allowOAuthCache: Bool
    
    let methods: [ExtractionMethod]
    
    private let log = OSLog(YouTube.self)
    
    /// - parameter methods: Methods used to extract streams from the video - ordered by priority (Default: `local` on iOS, macOS, tvOS, visionOS; `remote` on watchOS)
    public init(videoID: String, proxies: [String: URL] = [:], useOAuth: Bool = false, allowOAuthCache: Bool = false, methods: [ExtractionMethod] = .default) {
        self.videoID = videoID
        self.useOAuth = useOAuth
        self.allowOAuthCache = allowOAuthCache
        // TODO: install proxies if needed
        
        if methods.isEmpty {
#if canImport(JavaScriptCore)
            self.methods = [.local]
#else
            self.methods = [.remote]
#endif
        } else {
            self.methods = methods.removeDuplicates()
        }
    }
    
    /// - parameter methods: Methods used to extract streams from the video - ordered by priority (Default: `local` on iOS, macOS, tvOS, visionOS; `remote` on watchOS)
    public convenience init(url: URL, proxies: [String: URL] = [:], useOAuth: Bool = false, allowOAuthCache: Bool = false, methods: [ExtractionMethod] = .default) {
        let videoID = Extraction.extractVideoID(from: url.absoluteString) ?? ""
        self.init(videoID: videoID, proxies: proxies, useOAuth: useOAuth, allowOAuthCache: allowOAuthCache, methods: methods)
    }
    
    
    private var watchHTML: String {
        get async throws {
            if let cached = _watchHTML {
                return cached
            }
            var request = URLRequest(url: extendedWatchURL)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en", forHTTPHeaderField: "accept-language")
            request.httpShouldHandleCookies = false
            let (data, _) = try await YouTubeNetwork.session.data(for: request)
            _watchHTML = String(data: data, encoding: .utf8) ?? ""
            return _watchHTML!
        }
    }
    
    private var embedHTML: String {
        get async throws {
            if let cached = _embedHTML {
                return cached
            }
            var request = URLRequest(url: embedURL)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en", forHTTPHeaderField: "accept-language")
            request.setValue("https://www.reddit.com/", forHTTPHeaderField: "Referer")
            request.httpShouldHandleCookies = false
            let (data, _) = try await YouTubeNetwork.session.data(for: request)
            _embedHTML = String(data: data, encoding: .utf8) ?? ""
            return _embedHTML!
        }
    }
    
    
    /// check whether the video is available
    public func checkAvailability() async throws {
        let (status, messages) = try Extraction.playabilityStatus(watchHTML: await watchHTML)

        switch status {
        case .unplayable:
            if messages.contains(where: { $0.starts(with: "Join this channel to get access to members-only content") }) {
                throw YouTubeKitError.membersOnly
            }
        case .loginRequired:
            if messages.contains(where: {
                $0 == "Private video" || $0.starts(with: "This is a private video") || $0.starts(with: "This video is private")
            }) {
                throw YouTubeKitError.videoPrivate
            }
        case .error:
            throw YouTubeKitError.videoUnavailable
        case .liveStream:
            let streamingData = try await videoInfos.map { $0.streamingData }
            if streamingData.allSatisfy({ $0?.hlsManifestUrl == nil }) {
                throw YouTubeKitError.liveStreamError
            }
        case .ok, .none:
            break
        }
    }
    
    public var ageRestricted: Bool {
        get async throws {
            if let cached = _ageRestricted {
                return cached
            }
            
            _ageRestricted = try await Extraction.isAgeRestricted(watchHTML: watchHTML)
            return _ageRestricted!
        }
    }
    
    var jsURL: URL {
        get async throws {
            if let cached = _jsURL {
                return cached
            }
            
            if try await ageRestricted {
                _jsURL = try await URL(string: Extraction.jsURL(html: embedHTML))!
            } else {
                _jsURL = try await URL(string: Extraction.jsURL(html: watchHTML))!
            }
            return _jsURL!
        }
    }
    
    var js: String {
        get async throws {
            if let cached = _js {
                return cached
            }
            
            let jsURL = try await jsURL
            
            if let cached = Self.scriptCache.object(forKey: jsURL as NSURL) {
                _js = cached as String
            } else {
                let diskURL = Self.scriptDiskURL(for: jsURL)
                if let diskText = try? String(contentsOf: diskURL, encoding: .utf8), !diskText.isEmpty {
                    _js = diskText
                    Self.scriptCache.setObject(diskText as NSString, forKey: jsURL as NSURL, cost: diskText.utf8.count)
                } else {
                    var request = URLRequest(url: jsURL, timeoutInterval: 8)
                    request.httpShouldHandleCookies = false
                    request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                    let (data, response) = try await YouTubeNetwork.session.data(for: request)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                          let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw YouTubeKitError.extractError }
                    _js = text
                    Self.scriptCache.setObject(text as NSString, forKey: jsURL as NSURL, cost: data.count)
                    try? data.write(to: diskURL, options: .atomic)
                    Self.trimDiskScripts()
                }
            }
            return _js!
        }
    }

    var signatureTimestamp: Int? {
        get async throws {
            if let cached = _signatureTimestamp {
                return cached
            }
            
            _signatureTimestamp = try await Extraction.extractSignatureTimestamp(fromJS: js)
            return _signatureTimestamp
        }
    }
    
    var ytcfg: Extraction.YtCfg {
        get async throws {
            if let cached = _ytcfg {
                return cached
            }
            
            _ytcfg = try await Extraction.extractYtCfg(from: watchHTML)
            return _ytcfg!
        }
    }
    
    /// Interface to query both adaptive (DASH) and progressive streams.
    /// Returns a list of streams if they have been initialized.
    /// If the streams have not been initialized, finds all relevant streams and initializes them.
    public var streams: [Stream] {
        get async throws {
            try await checkAvailability()
            if let cached = _fmtStreams {
                return cached
            }
            
            let result = try await Task.retry(with: methods) { method in
                switch method {
#if canImport(JavaScriptCore)
                case .local:
                    let allStreamingData = try await self.streamingData
                    let videoInfos = try await self.videoInfos
                    
                    var streams = [Stream]()
                    var existingITags = Set<Int>()
                    
                    func process(streamingData: InnerTube.StreamingData, videoInfo: InnerTube.VideoInfo) async throws {
                        
                        try Task.checkCancellation()
                        var streamManifest = Extraction.applyDescrambler(streamData: streamingData)
                        if audioOnly { streamManifest.removeAll { !$0.mimeType.hasPrefix("audio/") } }
                        streamManifest = Extraction.filterOutDubbedAudio(streamManifest: streamManifest)
                        guard !streamManifest.isEmpty else { return }

                        do {
                            try await Extraction.applySignature(streamManifest: &streamManifest, videoInfo: videoInfo, js: js)
                        } catch {
                            // to force an update to the js file, we clear the cache and retry
                            _js = nil
                            _jsURL = nil
                            YouTube.clearScriptCaches()
                            try await Extraction.applySignature(streamManifest: &streamManifest, videoInfo: videoInfo, js: js)
                        }
                        
                        let newStreams = streamManifest.compactMap { try? Stream(format: $0) }
                        
                        // make sure only one stream per itag exists
                        for stream in newStreams {
                            if existingITags.insert(stream.itag.itag).inserted {
                                streams.append(stream)
                            }
                        }
                    }
                    
                    for (streamingData, videoInfo) in zip(allStreamingData, videoInfos) {
                        try await process(streamingData: streamingData, videoInfo: videoInfo)
                    }
                    
                    // This client also supplies alternate AAC renditions. Retain it for
                    // audio-only callers: finding an AAC URL does not prove it will pass
                    // the caller's media-header/duration validation.
                    if !streams.contains(where: { $0.includesVideoAndAudioTrack }) {
                        if let videoInfo = try? await loadAdditionalVideoInfos(forClient: .mediaConnectFrontend), let streamingData = videoInfo.streamingData {
                            os_log("Found no progressive streams. Called mediaConnectFrontend client to get additional video infos", log: log, type: .info)
                            try await process(streamingData: streamingData, videoInfo: videoInfo)
                        }
                    }
                    
                    return streams
#endif
                    
                case .remote(let serverURL):
                    let remoteClient = RemoteYouTubeClient(serverURL: serverURL)
                    let remoteStreams = try await remoteClient.extractStreams(forVideoID: videoID)
                    
                    return remoteStreams.compactMap { try? Stream(remoteStream: $0) }
                }
            }
            
            _fmtStreams = result
            return result
        }
    }
    
    /// Reuse the short-lived player context across recordings. This warms scripts, never audio.
    public func prepareAudioContext() async throws {
        _ = try await audioContext()
    }

    private func audioContext() async throws -> FastAudioContextCache.Context {
        try await FastAudioContextCache.shared.value { [self] in
            let source = try await js
            let config = try await ytcfg
            return .init(source: source, config: config)
        }
    }

    /// Scores M4A/AAC streams so default and data-saver modes prefer clean ~128 kbps AAC-LC
    /// (~57 MB/hr) over muffled 48 kbps or heavy 256+ kbps, while explicit high quality prefers max bitrate.
    public static func audioPreferenceScore(bitrate: Int, aacLC: Bool, dataSaver: Bool, highQuality: Bool) -> Int {
        let clampedBitrate = min(max(0, bitrate), 1_000_000)
        if highQuality {
            return 4_000_000 + clampedBitrate + (aacLC ? 1 : 0)
        }
        let tier: Int
        if (96_000...165_000).contains(clampedBitrate) {
            tier = 4
        } else if dataSaver {
            tier = clampedBitrate > 0 && clampedBitrate < 96_000 ? 3 : (clampedBitrate > 165_000 ? 2 : 1)
        } else {
            tier = clampedBitrate > 165_000 ? 3 : (clampedBitrate > 0 ? 2 : 1)
        }
        let bitrateComponent = (dataSaver && tier != 4) ? (1_000_000 - clampedBitrate) : clampedBitrate
        return tier * 2_000_000 + bitrateComponent + (aacLC ? 1 : 0)
    }

    public static func sortAudioStreams(_ streams: [Stream], dataSaver: Bool, highQuality: Bool) -> [Stream] {
        streams.sorted { lhs, rhs in
            let leftBps = lhs.bitrate ?? (lhs.itag.audioBitrate.map { $0 * 1000 } ?? 0)
            let rightBps = rhs.bitrate ?? (rhs.itag.audioBitrate.map { $0 * 1000 } ?? 0)
            let leftAAC: Bool = { if case .mp4a("40.2") = lhs.audioCodec { return true }; return false }()
            let rightAAC: Bool = { if case .mp4a("40.2") = rhs.audioCodec { return true }; return false }()
            let leftScore = audioPreferenceScore(bitrate: leftBps, aacLC: leftAAC, dataSaver: dataSaver, highQuality: highQuality)
            let rightScore = audioPreferenceScore(bitrate: rightBps, aacLC: rightAAC, dataSaver: dataSaver, highQuality: highQuality)
            return leftScore > rightScore
        }
    }

    private func resolveDirectAudio(client: InnerTube.ClientType,
                                    ytcfg: Extraction.YtCfg,
                                    dataSaver: Bool,
                                    highQuality: Bool,
                                    availability: AudioAvailabilityState,
                                    validate: @escaping @Sendable (Stream) async throws -> Bool) async throws -> Stream? {
        let tube = InnerTube(client: client, signatureTimestamp: nil, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
        let info = try await tube.player(videoID: videoID)
        try Task.checkCancellation()
        if info.videoDetails?.videoId == nil || info.videoDetails?.videoId == videoID {
            await availability.record(info.playabilityStatus?.status)
        }
        guard info.videoDetails?.videoId == videoID,
              info.playabilityStatus?.status == "OK", let data = info.streamingData else { return nil }
        var manifest = Extraction.applyDescrambler(streamData: data)
        manifest.removeAll { !$0.mimeType.hasPrefix("audio/mp4") || Extraction.needsSignatureOrN($0) }
        manifest = Extraction.filterOutDubbedAudio(streamManifest: manifest)
        guard !manifest.isEmpty else { return nil }
        let candidates = Self.sortAudioStreams(manifest.compactMap { try? Stream(format: $0) }, dataSaver: dataSaver, highQuality: highQuality)
        for stream in candidates where stream.isNativelyPlayable {
            try Task.checkCancellation()
            if try await validate(stream) { return stream }
        }
        return nil
    }

    /// Resolve and validate AAC as clients finish, prioritizing direct zero-JS mobile clients
    /// before downloading watch HTML or running base.js challenge solvers.
    public func firstPlayableAudioStream(dataSaver: Bool = false,
                                         highQuality: Bool = false,
                                         validate: @escaping @Sendable (Stream) async throws -> Bool) async throws -> Stream {
        let availability = AudioAvailabilityState()
        do {
        return try await AudioExtractionFallback.value(fast: { [self] in
            try Task.checkCancellation()

            // Tier 1: Direct iOS client requires zero watchHTML, zero visitorData, and zero player JS.
            if let direct = try? await resolveDirectAudio(client: .ios, ytcfg: .empty, dataSaver: dataSaver, highQuality: highQuality, availability: availability, validate: validate) {
                return direct
            }
            try Task.checkCancellation()

            // Tier 2: Fetch lightweight visitorData only (no 3MB base.js) and race direct mobile/VR clients.
            if let visitorCfg = try? await FastVisitorCache.shared.value({ [self] in try await self.ytcfg }) {
                try Task.checkCancellation()
                let directClients: [InnerTube.ClientType] = [.androidVR, .visionOS, .ios]
                let tier2Winner = try await withThrowingTaskGroup(of: Stream?.self) { group -> Stream? in
                    for (index, client) in directClients.enumerated() {
                        group.addTask { [self] in
                            do {
                                if dataSaver && index > 0 { try await Task.sleep(nanoseconds: UInt64(index) * 120_000_000) }
                                else if index >= 2 { try await Task.sleep(nanoseconds: 180_000_000) }
                                return try await self.resolveDirectAudio(client: client, ytcfg: visitorCfg, dataSaver: dataSaver, highQuality: highQuality, availability: availability, validate: validate)
                            } catch is CancellationError { throw CancellationError() }
                            catch { try Task.checkCancellation(); return nil }
                        }
                    }
                    defer { group.cancelAll() }
                    while let result = try await group.next() {
                        try Task.checkCancellation()
                        if let result { return result }
                    }
                    return nil
                }
                if let tier2Winner { return tier2Winner }
                await FastVisitorCache.shared.invalidate()
            }
            try Task.checkCancellation()

            // Tier 3: Full JS-backed extraction path for tracks that require player signature solving.
            #if canImport(JavaScriptCore)
            let context = try await audioContext()
            let source = context.source
            let timestamp = Extraction.extractSignatureTimestamp(fromJS: source)
            let config = context.config
            let clients: [InnerTube.ClientType] = [.tvSamsung, .visionOS, .androidVR, .web, .mediaConnectFrontend]
            let winner = try await withThrowingTaskGroup(of: Stream?.self) { group -> Stream? in
                for (index, client) in clients.enumerated() {
                    group.addTask { [videoID, useOAuth, allowOAuthCache] in
                        do {
                            if dataSaver && index > 0 { try await Task.sleep(nanoseconds: UInt64(index) * 120_000_000) }
                            else if index >= 2 { try await Task.sleep(nanoseconds: 200_000_000) }
                            let tube = InnerTube(client: client, signatureTimestamp: timestamp, ytcfg: config,
                                                 useOAuth: useOAuth, allowCache: allowOAuthCache)
                            let info = try await tube.player(videoID: videoID)
                            #if DEBUG
                            if ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_TIMING"] == "1" {
                                print("YOUTUBE_AUDIO client=\(client.rawValue) id=\(videoID) status=\(info.playabilityStatus?.status ?? "unknown") reason=\(info.playabilityStatus?.reason ?? "")")
                            }
                            #endif
                            try Task.checkCancellation()
                            if info.videoDetails?.videoId == nil || info.videoDetails?.videoId == videoID {
                                await availability.record(info.playabilityStatus?.status)
                            }
                            guard info.videoDetails?.videoId == videoID,
                                  info.playabilityStatus?.status == "OK", let data = info.streamingData else { return nil }
                            var manifest = Extraction.applyDescrambler(streamData: data)
                            manifest.removeAll { !$0.mimeType.hasPrefix("audio/mp4") }
                            manifest = Extraction.filterOutDubbedAudio(streamManifest: manifest)
                            guard !manifest.isEmpty else { return nil }
                            try Extraction.applySignature(streamManifest: &manifest, videoInfo: info, js: source)
                            try Task.checkCancellation()
                            let streams = Self.sortAudioStreams(manifest.compactMap { try? Stream(format: $0) }, dataSaver: dataSaver, highQuality: highQuality)
                            for stream in streams where stream.isNativelyPlayable {
                                try Task.checkCancellation()
                                if try await validate(stream) { return stream }
                            }
                            return nil
                        } catch is CancellationError { throw CancellationError() }
                        catch { try Task.checkCancellation(); return nil }
                    }
                }
                defer { group.cancelAll() }
                while let result = try await group.next() {
                    try Task.checkCancellation()
                    if let result { return result }
                }
                return nil
            }
            if let winner { return winner }
            await FastAudioContextCache.shared.invalidate()
            #endif
            return nil
        }, fallback: { [self] in
            // Keep all existing extraction alternatives if fast clients are unavailable.
            let fallback = Self.sortAudioStreams(
                try await streams.filterAudioOnly().filter { $0.fileExtension == .m4a && $0.isNativelyPlayable },
                dataSaver: dataSaver,
                highQuality: highQuality
            )
            if !fallback.isEmpty { await availability.record("OK") }
            for stream in fallback {
                try Task.checkCancellation()
                if try await validate(stream) { return stream }
            }
            throw YouTubeKitError.extractError
        })
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            if let failure = await availability.failure() { throw failure }
            throw error
        }
    }

    /// Returns a list of live streams - currently only HLS supported
    /// - Note: Currently doesn't respect `method` set. It always uses `.local`
    public var livestreams: [Livestream] {
        get async throws {
            var livestreams = [Livestream]()
            let hlsURLs = try await streamingData.compactMap { $0.hlsManifestUrl }.compactMap { URL(string: $0) }
            livestreams.append(contentsOf: hlsURLs.map { Livestream(url: $0, streamType: .hls) })
            return livestreams
        }
    }

    /// streaming data from video info
    var streamingData: [InnerTube.StreamingData] {
        get async throws {
            let streamingData = try await videoInfos.compactMap { $0.streamingData }
            if !streamingData.isEmpty {
                return streamingData
            } else {
                if let videoInfo = try? await loadAdditionalVideoInfos(forClient: .webEmbed), let streamingData = videoInfo.streamingData {
                    _videoInfos = [videoInfo]
                    return [streamingData]
                }

                try await bypassAgeGate()
                let streamingData = try await videoInfos.compactMap { $0.streamingData }
                if !streamingData.isEmpty {
                    return streamingData
                } else {
                    throw YouTubeKitError.extractError
                }
            }
        }
    }

    /// Video details from video info.
    var videoDetails: [InnerTube.VideoInfo.VideoDetails] {
        get async throws {
            try await videoInfos.compactMap { $0.videoDetails }
        }
    }
    
    var videoInfos: [InnerTube.VideoInfo] {
        get async throws {
            if let cached = _videoInfos {
                return cached
            }
            
            // try extracting video infos from watch html directly as well
            let watchVideoInfoTask = Task<InnerTube.VideoInfo?, Never> { [log] in
                do {
                    return nil //try await Extraction.getVideoInfo(fromHTML: watchHTML)  // (temporarily disabled)
                } catch let error {
                    os_log("Couldn't extract video info from main watch html: %{public}@", log: log, type: .debug, error.localizedDescription)
                    return nil
                }
            }

            let signatureTimestamp = try await signatureTimestamp
            let ytcfg = try await ytcfg
            
            let innertubeClients: [InnerTube.ClientType] = [.ios, .androidVR, .tvSamsung, .visionOS, .web]
            
            let results: [Result<InnerTube.VideoInfo, Error>] = await innertubeClients.concurrentMap { [videoID, useOAuth, allowOAuthCache] client in
                let innertube = InnerTube(client: client, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
                
                do {
                    let innertubeResponse = try await innertube.player(videoID: videoID)
                    return .success(innertubeResponse)
                } catch let error {
                    return .failure(error)
                }
            }
            
            var videoInfos = [InnerTube.VideoInfo]()
            var errors = [Error]()
            
            for result in results {
                switch result {
                case .success(let innertubeResponse):
                    videoInfos.append(innertubeResponse)
                case .failure(let error):
                    errors.append(error)
                }
            }
            
            // append potentially extracted video info (with least priority)
            if let watchVideoInfo = await watchVideoInfoTask.value {
                videoInfos.append(watchVideoInfo)
            }
            
            // remove video infos with incorrect videoID
            for (i, videoInfo) in videoInfos.enumerated() where videoInfo.videoDetails?.videoId != videoID {
                os_log("Skipping player response from client %{public}i. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, i, videoInfo.videoDetails?.videoId ?? "nil", videoID)
            }
            videoInfos = videoInfos.filter { $0.videoDetails?.videoId == videoID }
            
            if videoInfos.isEmpty {
                throw errors.first ?? YouTubeKitError.extractError
            }
            
            _videoInfos = videoInfos
            return videoInfos
        }
    }
    
    private func loadAdditionalVideoInfos(forClient client: InnerTube.ClientType) async throws -> InnerTube.VideoInfo {
        let signatureTimestamp = try await signatureTimestamp
        let ytcfg = if client == .webEmbed {
            try await Extraction.extractYtCfg(from: embedHTML)
        } else {
            try await ytcfg
        }
        let innertube = InnerTube(client: client, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
        let videoInfo = try await innertube.player(videoID: videoID)
        
        // ignore if incorrect videoID
        if videoInfo.videoDetails?.videoId != videoID {
            os_log("Skipping player response from %{public}@ client. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, client.rawValue, videoInfo.videoDetails?.videoId ?? "nil", videoID)
            throw YouTubeKitError.extractError
        }
        
        return videoInfo
    }
    
    private func bypassAgeGate() async throws {
        let signatureTimestamp = try await signatureTimestamp
        let ytcfg = try await ytcfg
        let innertube = InnerTube(client: .webCreator, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
        let innertubeResponse = try await innertube.player(videoID: videoID)

        if innertubeResponse.playabilityStatus?.status == "UNPLAYABLE" || innertubeResponse.playabilityStatus?.status == "LOGIN_REQUIRED" {
            throw YouTubeKitError.videoAgeRestricted
        }

        if innertubeResponse.videoDetails?.videoId != videoID {
            os_log("Skipping player response from webCreator client. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, innertubeResponse.videoDetails?.videoId ?? "nil", videoID)
            throw YouTubeKitError.extractError
        }

        _videoInfos = [innertubeResponse]
    }
    
    /// Interface to query both adaptive (DASH) and progressive streams.
    /*public var streams: StreamQuery {
        get async throws {
            //try await checkAvailability()
            return StreamQuery(fmtStreams: try await fmtStreams)
        }
    }*/
    
}


/// Coalesces lightweight visitorData fetches without downloading large player JS scripts.
@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
actor FastVisitorCache {
    static let shared = FastVisitorCache()
    private var cached: (Date, Extraction.YtCfg)?
    private struct Request {
        let token: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Extraction.YtCfg, Error>]
    }
    private var pending: Request?

    func value(_ loader: @escaping @Sendable () async throws -> Extraction.YtCfg) async throws -> Extraction.YtCfg {
        try Task.checkCancellation()
        let waiter = UUID()
        let config = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Extraction.YtCfg, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if let (date, config) = cached, Date().timeIntervalSince(date) < 1800 {
                    continuation.resume(returning: config)
                } else if var request = pending {
                    request.waiters[waiter] = continuation; pending = request
                } else {
                    let token = UUID()
                    let task = Task {
                        do { self.finish(token: token, result: .success(try await loader())) }
                        catch { self.finish(token: token, result: .failure(error)) }
                    }
                    pending = Request(token: token, task: task, waiters: [waiter: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(waiter: waiter) }
        }
        try Task.checkCancellation()
        return config
    }

    private func cancel(waiter: UUID) {
        guard var request = pending, let continuation = request.waiters.removeValue(forKey: waiter) else { return }
        if request.waiters.isEmpty { pending = nil; request.task.cancel() }
        else { pending = request }
        continuation.resume(throwing: CancellationError())
    }

    private func finish(token: UUID, result: Result<Extraction.YtCfg, Error>) {
        guard let request = pending, request.token == token else { return }
        pending = nil
        if case .success(let config) = result { cached = (Date(), config) }
        for continuation in request.waiters.values { continuation.resume(with: result) }
    }

    func invalidate() { cached = nil }
}

/// Actor isolation coalesces cold watch/player fetches from concurrent song selections.
@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
actor FastAudioContextCache {
    struct Context {
        let source: String
        let config: Extraction.YtCfg
    }
    static let shared = FastAudioContextCache()
    private var cached: (Date, Context)?
    private struct Request {
        let token: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Context, Error>]
    }
    private var pending: Request?
    #if DEBUG
    private var completedRequests = 0
    func waiterCount() -> Int { pending?.waiters.count ?? 0 }
    func completionCount() -> Int { completedRequests }
    #endif
    func value(loader: @escaping () async throws -> Context) async throws -> Context {
        try Task.checkCancellation()
        let waiter = UUID()
        let context = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Context, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if let (date, context) = cached, Date().timeIntervalSince(date) < 1800 {
                    continuation.resume(returning: context)
                } else if var request = pending {
                    request.waiters[waiter] = continuation; pending = request
                } else {
                    let token = UUID()
                    let task = Task {
                        do { self.finish(token: token, result: .success(try await loader())) }
                        catch { self.finish(token: token, result: .failure(error)) }
                    }
                    pending = Request(token: token, task: task, waiters: [waiter: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(waiter: waiter) }
        }
        try Task.checkCancellation()
        return context
    }
    private func cancel(waiter: UUID) {
        guard var request = pending, let continuation = request.waiters.removeValue(forKey: waiter) else { return }
        if request.waiters.isEmpty { pending = nil; request.task.cancel() }
        else { pending = request }
        continuation.resume(throwing: CancellationError())
    }
    private func finish(token: UUID, result: Result<Context, Error>) {
        #if DEBUG
        completedRequests += 1
        #endif
        // A canceled loader can finish after a new song has started its own context request.
        guard let request = pending, request.token == token else { return }
        pending = nil
        if case .success(let context) = result { cached = (Date(), context) }
        for continuation in request.waiters.values { continuation.resume(with: result) }
    }
    func invalidate() { cached = nil }
}

/// Ordinary fast-path failures may retry through the complete extractor. Cancellation must never start another request.
@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
enum AudioExtractionFallback {
    static func value<Value>(fast: () async throws -> Value?, fallback: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        do {
            if let value = try await fast() {
                try Task.checkCancellation()
                return value
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
        }
        try Task.checkCancellation()
        return try await fallback()
    }
}

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
actor AudioAvailabilityState {
    private var sawOK = false
    private var loginRequired = false
    private var unavailable = false
    func record(_ status: String?) {
        if status == "OK" { sawOK = true }
        if status == "LOGIN_REQUIRED" { loginRequired = true }
        if status == "UNPLAYABLE" || status == "ERROR" { unavailable = true }
    }
    func failure() -> AudioStreamFailure? {
        guard !sawOK else { return nil }
        if loginRequired { return .authenticationRequired }
        return unavailable ? .unavailable : nil
    }
}

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
enum YouTubeNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate, br"]
        return URLSession(configuration: config)
    }()
}
