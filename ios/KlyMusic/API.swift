import Foundation

enum PlaybackRace {
    /// A failing or slow candidate must not block another validated recording.
    static func first<Value: Sendable>(_ operations: [@Sendable () async throws -> Value], limit: Int = .max) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            var next = 0
            let width = min(operations.count, max(1, limit))
            for _ in 0..<width { group.addTask(operation: operations[next]); next += 1 }
            defer { group.cancelAll() }
            var failure: Error = APIError.invalidResponse
            while !group.isEmpty {
                do {
                    if let result = try await group.next() {
                        try Task.checkCancellation()
                        return result
                    }
                } catch {
                    try Task.checkCancellation()
                    failure = error
                    if next < operations.count { group.addTask(operation: operations[next]); next += 1 }
                }
            }
            try Task.checkCancellation()
            throw failure
        }
    }
}

enum PlaybackPreferences {
    static func savesData(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "lowDataMode") == nil || defaults.bool(forKey: "lowDataMode")
    }
    static func quality(_ defaults: UserDefaults = .standard) -> String {
        savesData(defaults) ? "data" : defaults.string(forKey: "quality") ?? "auto"
    }
    static func browseWarmupAllowed(savesData: Bool, unmetered: Bool) -> Bool { !savesData && unmetered }
    static func audioMegabytesPerHour(kilobits: Int) -> Double { Double(kilobits) * 0.45 }
}

/// Saves the identity of a successfully validated recording, never expiring CDN
/// credentials. Replays can skip catalogue matching while obtaining fresh URLs.
actor RecordingMatchStore {
    static let shared = RecordingMatchStore()
    private struct Entry: Codable {
        var requested: Track
        var candidate: Track
        var saved: Date
    }
    private let file: URL
    private var entries: [String: Entry]
    init(file: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("verified-recordings-v1.json")) {
        self.file = file
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: file))) ?? [:]
    }
    private func key(_ track: Track, locale: String) -> String { locale + "|" + track.id }
    func candidate(for track: Track, locale: String) -> Track? {
        guard let entry = entries[key(track, locale: locale)], Date().timeIntervalSince(entry.saved) < 7 * 86400,
              NativeCatalog.match(track, entry.candidate) >= 0.9 else { return nil }
        return entry.candidate
    }
    func details(for track: Track, locale: String) -> Track? {
        guard let entry = entries[key(track, locale: locale)], Date().timeIntervalSince(entry.saved) < 7 * 86400,
              NativeCatalog.canonical(entry.requested.title) == NativeCatalog.canonical(track.title),
              NativeCatalog.normalized(entry.requested.artist) == NativeCatalog.normalized(track.artist) else { return nil }
        var result = track
        if !result.duration.isFinite || result.duration <= 0 { result.duration = entry.requested.duration }
        if result.album.isEmpty { result.album = entry.requested.album }
        return result
    }
    func save(_ candidate: Track, for track: Track, locale: String) {
        guard NativeCatalog.match(track, candidate) >= 0.9 else { return }
        entries[key(track, locale: locale)] = Entry(requested: track, candidate: candidate, saved: .now)
        if entries.count > 160, let oldest = entries.min(by: { $0.value.saved < $1.value.saved })?.key { entries[oldest] = nil }
        persist()
    }
    func remove(_ track: Track, locale: String) { entries[key(track, locale: locale)] = nil; persist() }
    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}

enum APIError: LocalizedError {
    case configuration, server(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .configuration: return L("Müzik bağlantısı şu anda kurulamıyor. Yeniden dene.")
        case .server(let message): return message
        case .invalidResponse: return L("Beklenmeyen bir yanıt geldi. Yeniden dene.")
        }
    }
}

/// Shares one resolution across browsing, playback and downloads. Each caller owns its
/// wait independently, so leaving a screen never cancels another caller's playback.
actor PlaybackAssetCache {
    private struct Entry { var asset: PlaybackAsset; var accessed: UInt64 }
    private struct Request {
        var token: UUID
        var task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<PlaybackAsset, Error>]
    }
    private let capacity: Int
    private var tick: UInt64 = 0
    private var entries: [String: Entry] = [:]
    private var requests: [String: Request] = [:]

    init(capacity: Int = 48) { self.capacity = max(1, capacity) }

    func value(for key: String, loader: @escaping @Sendable () async throws -> PlaybackAsset) async throws -> PlaybackAsset {
        try Task.checkCancellation()
        let waiter = UUID()
        let asset = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PlaybackAsset, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let minimumExpiry = Date().timeIntervalSince1970 + 120
                entries = entries.filter { $0.value.asset.expiresAt > minimumExpiry }
                if var entry = entries[key] {
                    tick &+= 1; entry.accessed = tick; entries[key] = entry
                    continuation.resume(returning: entry.asset)
                } else if var request = requests[key] {
                    request.waiters[waiter] = continuation; requests[key] = request
                } else {
                    let token = UUID()
                    let task = Task {
                        do { self.finish(key, token: token, result: .success(try await loader())) }
                        catch { self.finish(key, token: token, result: .failure(error)) }
                    }
                    requests[key] = Request(token: token, task: task, waiters: [waiter: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(key, waiter: waiter) }
        }
        try Task.checkCancellation()
        return asset
    }

    func invalidate() { entries.removeAll() }

    private func cancel(_ key: String, waiter: UUID) {
        guard var request = requests[key], let continuation = request.waiters.removeValue(forKey: waiter) else { return }
        if request.waiters.isEmpty {
            requests[key] = nil
            request.task.cancel()
        } else { requests[key] = request }
        continuation.resume(throwing: CancellationError())
    }

    private func finish(_ key: String, token: UUID, result: Result<PlaybackAsset, Error>) {
        // A canceled request may finish after a newer request for the same song.
        guard let request = requests[key], request.token == token else { return }
        requests[key] = nil
        if case .success(let asset) = result, asset.expiresAt > Date().timeIntervalSince1970 + 120 {
            tick &+= 1; entries[key] = Entry(asset: asset, accessed: tick)
            if entries.count > capacity, let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key {
                entries[oldest] = nil
            }
        }
        for continuation in request.waiters.values { continuation.resume(with: result) }
    }
}

actor API {
    private struct Failure: Decodable { var detail: String }
    static let shared = API()
    private let catalog = NativeCatalog()
    private let playbackCache = PlaybackAssetCache()
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 50
        session = URLSession(configuration: config)
    }

    /// Only explicit debug launch arguments can enable the development backend.
    /// Release builds always connect to the music sources directly.
    nonisolated static var endpoint: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-serverURL"), arguments.indices.contains(index + 1) { return arguments[index + 1] }
        #endif
        return "native"
    }

    nonisolated static func baseURL() throws -> URL {
        guard endpoint != "native", let url = URL(string: endpoint), let host = url.host,
              url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { throw APIError.configuration }
        return url
    }

    nonisolated static func mediaURL(_ asset: PlaybackAsset) throws -> URL {
        if let url = URL(string: asset.path), url.scheme != nil {
            guard NativeCatalog.allowedMediaURL(url) else { throw APIError.invalidResponse }
            return url
        }
        return try baseURL().appendingPathComponent(asset.path)
    }

    private func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        try Task.checkCancellation()
        let base = try Self.baseURL()
        guard var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.configuration }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw APIError.configuration }
        var request = URLRequest(url: url)
        request.setValue("KlyMusic-iOS/2.1", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data).detail) ?? L("Müzik bağlantısı şu anda kurulamıyor. Yeniden dene.")
            throw APIError.server(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func home() async throws -> HomeResponse {
        if Self.endpoint == "native" { return try await catalog.home() }
        return try await request("v1/home")
    }
    func search(_ text: String, source: String = "all") async throws -> SearchResponse {
        if Self.endpoint == "native" { return try await catalog.search(text, source: source) }
        return try await request("v1/search", query: [.init(name: "q", value: text), .init(name: "source", value: source)])
    }
    func categories() async throws -> [BrowseCategory] {
        if Self.endpoint == "native" { return try await catalog.categories() }
        struct Response: Decodable { var categories: [BrowseCategory] }
        let response: Response = try await request("v1/categories")
        return response.categories
    }
    func recommendations(for seeds: [Track]) async throws -> HomeResponse {
        if Self.endpoint == "native" { return try await catalog.recommendations(for: seeds) }
        return try await request("v1/recommendations")
    }
    func album(_ id: String) async throws -> AlbumResponse {
        if Self.endpoint == "native" { return try await catalog.album(id) }
        return try await request("v1/albums/" + id)
    }
    func artist(_ id: String) async throws -> ArtistResponse {
        if Self.endpoint == "native" { return try await catalog.artist(id) }
        return try await request("v1/artists/" + id)
    }
    func resolve(_ track: Track, provider: String = "auto", quality: String = "auto") async throws -> PlaybackAsset {
        let parts = [Self.endpoint, ListeningLocale.current.cacheKey, track.id, track.title, track.artist, track.album, String(track.duration), provider, quality]
        let key = parts.map { "\($0.utf8.count):" + $0 }.joined()
        return try await playbackCache.value(for: key) { [catalog] in
            if Self.endpoint == "native" { return try await catalog.resolve(track, provider: provider, quality: quality) }
            struct Body: Encodable { var track: Track; var provider: String; var quality: String }
            return try await self.request("v1/resolve", body: JSONEncoder().encode(Body(track: track, provider: provider, quality: quality)))
        }
    }
    func prepareMatches(_ tracks: [Track]) async {
        guard Self.endpoint == "native" else { return }
        await catalog.prepareMatches(tracks)
    }
    func invalidatePlayback() async { await playbackCache.invalidate() }
    func lyrics(_ track: Track) async throws -> LyricsResponse {
        if Self.endpoint == "native" { return try await catalog.lyrics(track) }
        return try await request("v1/lyrics", body: JSONEncoder().encode(track))
    }
}
