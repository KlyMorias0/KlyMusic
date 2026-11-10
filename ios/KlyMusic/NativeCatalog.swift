import Foundation
import CommonCrypto
import YouTubeKit

/// Catalogue, matching and playback resolution run on the phone. No user server configuration.
actor NativeCatalog {
    private typealias JSON = [String: Any]
    private let session: URLSession
    private var homeCache: (key: String, date: Date, response: HomeResponse)?
    private var homeTask: (key: String, token: UUID, task: Task<HomeResponse, Error>)?
    private var searches: [String: (Date, SearchResponse)] = [:]
    private var youtubeSearches: [String: (Date, [Track])] = [:]
    private var details: [String: (Date, Track)] = [:]
    private let candidateRequests = MatchRequestPool()
    private var candidateCache: [String: (Date, [Track])] = [:]
    private var categoryTask: (String, Task<[BrowseCategory], Error>)?
    private var recommendationCache: [String: (Date, HomeResponse)] = [:]
    private let recordingMatches = RecordingMatchStore.shared

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 35
        config.urlCache = URLCache(memoryCapacity: 12_000_000, diskCapacity: 60_000_000)
        session = URLSession(configuration: config)
    }

    func home() async throws -> HomeResponse {
        let locale = ListeningLocale.current
        if let cached = homeCache, cached.key == locale.cacheKey, Date().timeIntervalSince(cached.date) < 1800 { return cached.response }
        if let pending = homeTask, pending.key == locale.cacheKey { return try await pending.task.value }
        let token = UUID()
        let task = Task { try await self.loadHome(locale: locale) }
        homeTask = (locale.cacheKey, token, task)
        defer { if homeTask?.token == token { homeTask = nil } }
        let result = try await task.value
        if ListeningLocale.current.cacheKey == locale.cacheKey { homeCache = (locale.cacheKey, .now, result) }
        return result
    }

    private func loadHome(locale: ListeningLocale) async throws -> HomeResponse {
        let country = locale.countryCode
        let turkish = locale.languageCode == "tr"
        async let local = try? charts(country)
        async let global: [Track]? = country == "us" ? nil : try? await charts("us")
        async let calm = try? appleSearch(turkish ? "Türkçe akustik" : "chill", limit: 18, country: country)
        let (localRows, globalRows, calmRows) = await (local, global, calm)
        var sections: [HomeSection] = []
        var regional = localRows ?? []
        if regional.isEmpty {
            regional = (try? await appleSearch(turkish ? "Türkçe Pop" : "top hits", limit: 30, country: country).compactMap(Self.appleTrack)) ?? []
        }
        if !regional.isEmpty {
            sections.append(.init(id: "local-" + country, title: turkish ? "Türkiye’de şimdi" : "Senin bölgen", subtitle: "", tracks: regional))
        }
        if let globalRows, !globalRows.isEmpty { sections.append(.init(id: "global", title: "Dünyanın ritmi", subtitle: "", tracks: globalRows)) }
        let quiet = (calmRows ?? []).compactMap(Self.appleTrack)
        if !quiet.isEmpty { sections.append(.init(id: "calm-" + locale.cacheKey, title: "Biraz yavaşla", subtitle: "", tracks: quiet)) }
        guard !sections.isEmpty else { throw APIError.server(L("Katalog şu anda yüklenemiyor. Yeniden dene.")) }
        return HomeResponse(sections: sections)
    }

    private func charts(_ country: String) async throws -> [Track] {
        let root = try await json("https://rss.marketingtools.apple.com/api/v2/\(country)/music/most-played/50/songs.json")
        let rows = Self.at(root, "feed.results") as? [JSON] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let title = row["name"] as? String, let artist = row["artistName"] as? String else { return nil }
            return Track(id: "apple:" + id, title: title, artist: artist, artwork: Self.art(row["artworkUrl100"] as? String), artistID: row["artistId"] as? String)
        }
    }

    func search(_ text: String, source: String = "all") async throws -> SearchResponse {
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { return SearchResponse() }
        if source == "youtube" { return SearchResponse(tracks: try await youtubeSearch(query)) }
        if source == "saavn" { return SearchResponse(tracks: try await saavnSearch(query)) }
        let key = ListeningLocale.current.cacheKey + "|" + query.lowercased()
        if let (date, cached) = searches[key], Date().timeIntervalSince(date) < 600 { return cached }
        async let songs = try? appleSearch(query)
        async let albums = try? appleSearch(query, entity: "album", limit: 12)
        async let artists = try? appleSearch(query, entity: "musicArtist", limit: 10)
        let (songRows, albumRows, artistRows) = await (songs, albums, artists)
        try Task.checkCancellation()
        var tracks = (songRows ?? []).compactMap(Self.appleTrack)
        let terms = Self.normalized(query).split(separator: " ")
        func relevance(_ track: Track) -> Double {
            let words = Set(Self.normalized(track.artist + " " + track.title).split(separator: " "))
            return Double(terms.filter { words.contains($0) }.count) / Double(max(1, terms.count))
        }
        if tracks.isEmpty || (terms.count > 1 && (tracks.map(relevance).max() ?? 0) < 0.75) {
            let extra = (try? await youtubeSearch(query)) ?? []
            try Task.checkCancellation()
            let ids = Set(tracks.map(\.id))
            tracks.append(contentsOf: extra.filter { !ids.contains($0.id) })
        }
        if tracks.isEmpty && songRows == nil { throw APIError.server(L("Katalog bağlantısı şu anda kullanılamıyor.")) }
        tracks.sort { relevance($0) > relevance($1) }
        let collections: [MusicCollection] = (albumRows ?? []).compactMap { row in
            guard let id = row["collectionId"] as? NSNumber, let title = row["collectionName"] as? String else { return nil }
            return MusicCollection(id: id.stringValue, title: title, artist: row["artistName"] as? String ?? "", artwork: Self.art(row["artworkUrl100"] as? String))
        }
        let people: [MusicArtist] = (artistRows ?? []).compactMap { row in
            guard let id = row["artistId"] as? NSNumber, let name = row["artistName"] as? String else { return nil }
            return MusicArtist(id: id.stringValue, name: name, artwork: nil)
        }
        let result = SearchResponse(tracks: tracks, albums: collections, artists: people)
        if searches.count > 60 { searches.removeAll() }
        searches[key] = (.now, result)
        return result
    }

    private struct CategoryCache: Codable { var saved: Date; var categories: [BrowseCategory] }
    func categories() async throws -> [BrowseCategory] {
        let locale = ListeningLocale.current
        let key = "editorialCategories-v2-" + locale.cacheKey
        if let bytes = UserDefaults.standard.data(forKey: key), let cached = try? JSONDecoder().decode(CategoryCache.self, from: bytes),
           Date().timeIntervalSince(cached.saved) < 7 * 86400 { return cached.categories }
        if let pending = categoryTask, pending.0 == locale.cacheKey { return try await pending.1.value }
        let request = Task<[BrowseCategory], Error> {
            let page = try await self.publicMusicPage(path: "search", locale: locale)
            let result = Self.editorialCategories(page)
            guard !result.isEmpty else { throw APIError.invalidResponse }
            if let bytes = try? JSONEncoder().encode(CategoryCache(saved: Date(), categories: result)) { UserDefaults.standard.set(bytes, forKey: key) }
            return result
        }
        categoryTask = (locale.cacheKey, request)
        defer { if categoryTask?.0 == locale.cacheKey { categoryTask = nil } }
        return try await request.value
    }

    static func editorialCategories(_ page: [String: Any]) -> [BrowseCategory] {
        let sections = at(page, "data.0.data.sections") as? [JSON] ?? []
        let supported = Set(["pop", "hip hop rap", "hip hop", "k pop", "dance", "dans", "electronic", "elektronik", "acoustic", "akustik", "alternative", "alternatif", "rock", "metal", "jazz", "caz", "classical", "klasik", "blues", "r b", "country", "chill", "uyku", "focus", "fokus", "halk muzigi", "sanat muzigi"])
        var seen = Set<String>()
        return sections.flatMap { $0["items"] as? [JSON] ?? [] }.compactMap { item in
            guard let title = item["title"] as? String, supported.contains(normalized(title)),
                  let id = at(item, "contentDescriptor.identifiers.storeAdamID") as? String,
                  seen.insert(id).inserted, let url = at(item, "artwork.dictionary.url") as? String else { return nil }
            // Apple's editorial landscape image is used directly; no album-cover tint.
            let image = url.replacingOccurrences(of: "{w}", with: "640").replacingOccurrences(of: "{h}", with: "426")
                .replacingOccurrences(of: "{c}", with: "sr").replacingOccurrences(of: "{f}", with: "jpg")
            return BrowseCategory(id: id, title: title, query: title, artwork: image)
        }
    }

    func recommendations(for seeds: [Track]) async throws -> HomeResponse {
        var artists = Set<String>()
        let choices = Array(seeds.filter { !$0.artist.isEmpty && artists.insert(Self.normalized($0.artist)).inserted }.prefix(4))
        guard !choices.isEmpty else { return HomeResponse(sections: []) }
        let key = ListeningLocale.current.cacheKey + "|" + choices.map { $0.artist }.joined(separator: "|")
        let response: HomeResponse
        if let (date, cached) = recommendationCache[key], Date().timeIntervalSince(date) < 86400 { response = cached }
        else {
            let sections = await withTaskGroup(of: (Int, [Track]).self) { group in
                for (index, seed) in choices.enumerated() {
                    group.addTask {
                        guard !Task.isCancelled else { return (index, []) }
                        return (index, (try? await self.recommendationTracks(for: seed)) ?? [])
                    }
                }
                var results: [(Int, [Track])] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.compactMap { index, songs -> HomeSection? in
                    let seed = choices[index]
                    guard !songs.isEmpty else { return nil }
                    return HomeSection(id: "artist-" + (seed.artistID ?? Self.normalized(seed.artist)), title: "Senin için", subtitle: seed.artist + " dinlediğin için", tracks: songs)
                }
            }
            try Task.checkCancellation()
            response = HomeResponse(sections: sections)
            if recommendationCache.count > 12 { recommendationCache.removeAll() }
            if !sections.isEmpty { recommendationCache[key] = (Date(), response) }
        }
        return HomeResponse(sections: HomeFeed.distinct(response.sections, excluding: seeds))
    }

    private func recommendationTracks(for seed: Track) async throws -> [Track] {
        let rows = try await appleSearch(seed.artist, limit: 12)
        return rows.compactMap(Self.appleTrack).filter { track in
            if let id = seed.artistID { return track.artistID == id }
            return Self.normalized(track.artist) == Self.normalized(seed.artist)
        }
    }

    private func publicMusicPage(path: String, locale: ListeningLocale) async throws -> JSON {
        var parts = URLComponents(string: "https://music.apple.com/" + locale.countryCode + "/" + path)!
        parts.queryItems = [.init(name: "l", value: locale.languageCode)]
        var request = URLRequest(url: parts.url!, timeoutInterval: 8)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), bytes.count < 3_000_000,
              let html = String(data: bytes, encoding: .utf8),
              let pattern = try? NSRegularExpression(pattern: #"<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>"#, options: .dotMatchesLineSeparators),
              let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html), let data = String(html[range]).data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? JSON else { throw APIError.invalidResponse }
        return payload
    }

    func album(_ id: String) async throws -> AlbumResponse {
        AlbumResponse(tracks: try await lookup(id).compactMap(Self.appleTrack))
    }

    func artist(_ id: String) async throws -> ArtistResponse {
        async let songs = lookup(id)
        async let collections = try? lookup(id, entity: "album")
        async let page = try? publicMusicPage(path: "artist/" + id, locale: ListeningLocale.current)
        let (rows, albumRows, website) = try await (songs, collections, page)
        guard let row = rows.first(where: { $0["wrapperType"] as? String == "artist" }), let name = row["artistName"] as? String else { throw APIError.invalidResponse }
        let albums: [MusicCollection] = (albumRows ?? []).compactMap { row in
            guard let id = row["collectionId"] as? NSNumber, let title = row["collectionName"] as? String else { return nil }
            return .init(id: id.stringValue, title: title, artist: row["artistName"] as? String ?? name, artwork: Self.art(row["artworkUrl100"] as? String), releaseDate: row["releaseDate"] as? String)
        }.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        let sections = Self.at(website, "data.0.data.sections") as? [JSON] ?? []
        let header = sections.first(where: { $0["itemKind"] as? String == "artistDetailHeader" })
        let item = (header?["items"] as? [JSON])?.first
        let portrait = Self.art(Self.at(item, "circleArtwork.dictionary.url") as? String)
        let banner = Self.art(Self.at(item, "wideArtwork.dictionary.url") as? String)
        return ArtistResponse(artist: .init(id: id, name: name, artwork: portrait, banner: banner), tracks: rows.compactMap(Self.appleTrack), albums: albums, featured: albums.first)
    }

    func resolve(_ original: Track, provider: String = "auto", quality: String = "auto") async throws -> PlaybackAsset {
        try Task.checkCancellation()
        let track = try await recordingDetails(original)
        let locale = ListeningLocale.current.cacheKey
        let saved = await recordingMatches.candidate(for: track, locale: locale)
        let cached = saved.flatMap { candidate in
            (provider == "auto" ? ["youtube", "saavn"].contains(candidate.source) : candidate.source == provider) ? candidate : nil
        }
        var operations: [@Sendable () async throws -> PlaybackAsset] = []
        if let cached {
            operations.append { [self] in
                do {
                    let id = String(cached.id.split(separator: ":", maxSplits: 1).last ?? "")
                    return try await (cached.source == "saavn" ? saavnStream(id, quality: quality, duration: track.duration) : youtubeStream(id, quality: quality, expectedDuration: track.duration))
                } catch is CancellationError { throw CancellationError() }
                catch { try Task.checkCancellation(); await recordingMatches.remove(track, locale: locale); throw error }
            }
        }
        // YouTube Music's song catalogue is primary; Apple identity/artwork stay on the requested Track.
        let order = provider == "auto" ? ["youtube", "youtube-video", "saavn"] : provider == "youtube" ? ["youtube", "youtube-video"] : [provider]
        operations += order.enumerated().map { index, stage in
            { @Sendable [self] in
                let delay = index * 450 + (cached == nil ? 0 : 250)
                if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
                return try await resolveStage(track, stage: stage, quality: quality, locale: locale)
            }
        }
        do {
            return try await PlaybackRace.first(operations, limit: operations.count)
        } catch is CancellationError { throw CancellationError() }
        catch { throw APIError.server(L("Bu kaydın aynı sürümü kaynaklarda çalınamıyor. Başka bir sonuç dene.")) }
    }

    private func resolveStage(_ track: Track, stage: String, quality: String, locale: String) async throws -> PlaybackAsset {
        let source = stage == "youtube-video" ? "youtube" : stage
        guard ["youtube", "saavn"].contains(source) else { throw APIError.invalidResponse }
        try Task.checkCancellation()
        let candidates: [Track]
        if track.id.hasPrefix(source + ":"), stage != "youtube-video" { candidates = [track] }
        else { candidates = try await matchedCandidates(track, source: source, videosOnly: stage == "youtube-video") }
        trace("source=\(stage) requested=\(track.title) candidates=\(candidates.map { $0.id + ":" + $0.title }.joined(separator: ","))")
        guard !candidates.isEmpty else { throw APIError.invalidResponse }
        let asset = try await PlaybackRace.first(candidates.map { candidate in
            { @Sendable [self] in
                let id = String(candidate.id.split(separator: ":", maxSplits: 1).last ?? "")
                let expected = track.duration > 0 ? track.duration : candidate.duration
                let asset = try await (source == "saavn" ? saavnStream(id, quality: quality, duration: expected) : youtubeStream(id, quality: quality, expectedDuration: expected))
                guard Self.validResolvedDuration(track, candidate: candidate, actual: asset.duration) else { throw APIError.invalidResponse }
                return asset
            }
        }, limit: 2)
        try Task.checkCancellation()
        if let candidate = candidates.first(where: { $0.id == asset.id }) {
            var enriched = track; if enriched.duration <= 0 { enriched.duration = asset.duration }
            var copy = candidate; if copy.duration <= 0 { copy.duration = asset.duration }
            await recordingMatches.save(copy, for: enriched, locale: locale)
        }
        return asset
    }

    private func matchedCandidates(_ track: Track, source: String, videosOnly: Bool = false) async throws -> [Track] {
        let key = [ListeningLocale.current.cacheKey, source, videosOnly ? "videos" : "songs", track.id, Self.canonical(track.title), Self.normalized(track.artist), String(track.duration)].joined(separator: "|")
        if let (date, rows) = candidateCache[key], Date().timeIntervalSince(date) < 600 { return rows }
        let matches = try await candidateRequests.value(for: key) { [self] in
            try await loadMatchedCandidates(track, source: source, videosOnly: videosOnly)
        }
        try Task.checkCancellation()
        if !matches.isEmpty {
            if candidateCache.count > 80 { candidateCache.removeAll() }
            candidateCache[key] = (.now, matches)
        }
        return matches
    }

    private func loadMatchedCandidates(_ track: Track, source: String, videosOnly: Bool) async throws -> [Track] {
        for query in Self.candidateQueries(track) {
            let rows = try await (source == "saavn" ? saavnSearch(query) : youtubeSearch(query, videos: videosOnly))
            trace("search=\(source) query=\(query) rows=\(rows.count) sample=\(rows.prefix(3).map { $0.title + " / " + $0.artist + " / " + String($0.duration) }.joined(separator: ";"))")
            try Task.checkCancellation()
            var seen = Set<String>()
            let matches = Array(rows.filter { Self.validCandidate(track, $0, videosOnly: videosOnly) && seen.insert($0.id).inserted }
                .sorted { Self.match(track, $0) > Self.match(track, $1) }.prefix(3))
            if !matches.isEmpty { return matches }
        }
        return []
    }

    static func validCandidate(_ requested: Track, _ candidate: Track, videosOnly: Bool) -> Bool {
        guard sameRecordingIdentity(requested, candidate) else { return false }
        if candidate.duration > 0 { return requested.duration <= 0 || durationCompatible(expected: requested.duration, actual: candidate.duration) }
        // Video search may omit a duration. The actual media still must pass stream validation.
        return candidate.duration == 0 && videosOnly && requested.duration.isFinite && requested.duration > 0
    }
    static func validResolvedDuration(_ requested: Track, candidate: Track, actual: Double) -> Bool {
        guard actual.isFinite, actual > 0 else { return false }
        let expected = requested.duration > 0 ? requested.duration : candidate.duration
        if expected > 0 { return durationCompatible(expected: expected, actual: actual) }
        return requested.id.hasPrefix("youtube:") && requested.id == candidate.id
    }
    static func candidateQueries(_ track: Track) -> [String] {
        let full = track.artist + " " + canonical(track.title)
        let compact = bilingualTitleBase(track.title)
        guard compact != track.title else { return [full] }
        var seen = Set<String>()
        return [track.artist + " " + canonical(compact), canonical(compact), full].filter { seen.insert($0).inserted }
    }

    /// Prepare identities/player code only; no song audio is downloaded while browsing.
    func prepareMatches(_ tracks: [Track]) async {
        let visible = Array(tracks.prefix(3))
        let missing = visible.filter { $0.id.hasPrefix("apple:") && $0.duration <= 0 }
        if !missing.isEmpty {
            let ids = missing.map { String($0.id.dropFirst(6)) }.joined(separator: ",")
            if let rows = try? await json("https://itunes.apple.com/lookup", query: ["id": ids, "country": ListeningLocale.current.countryCode, "entity": "song"])["results"] as? [JSON] {
                for row in rows.compactMap(Self.appleTrack) {
                    details[ListeningLocale.current.cacheKey + "|" + row.id] = (.now, row)
                }
            }
        }
        for original in visible {
            guard !Task.isCancelled else { return }
            do {
                let track = try await recordingDetails(original)
                var candidates = track.id.hasPrefix("youtube:") ? [track] : try await matchedCandidates(track, source: "youtube")
                if candidates.isEmpty { candidates = try await matchedCandidates(track, source: "youtube", videosOnly: true) }
                if let first = candidates.first {
                    let video = YouTube(videoID: String(first.id.split(separator: ":").last ?? ""), methods: [.local])
                    try await video.prepareAudioContext()
                }
            } catch { if Task.isCancelled { return } }
        }
    }

    private func recordingDetails(_ original: Track) async throws -> Track {
        var track = original
        if let saved = await recordingMatches.details(for: original, locale: ListeningLocale.current.cacheKey) { track = saved }
        if track.id.hasPrefix("apple:"), !track.duration.isFinite || track.duration <= 0 {
            let key = ListeningLocale.current.cacheKey + "|" + track.id
            if let (date, cached) = details[key], Date().timeIntervalSince(date) < 3600 { track = cached }
            else {
                var rows = (try? await lookup(String(track.id.dropFirst(6)))) ?? []
                if rows.compactMap(Self.appleTrack).isEmpty, ListeningLocale.current.countryCode != "us" {
                    rows = (try? await lookup(String(track.id.dropFirst(6)), country: "us")) ?? []
                }
                if let enriched = rows.compactMap(Self.appleTrack).first(where: { $0.id == track.id }) {
                    track.duration = enriched.duration
                    if track.album.isEmpty { track.album = enriched.album }
                    if track.artwork == nil { track.artwork = enriched.artwork }
                }
                if details.count > 150 { details.removeAll() }
                if track.duration > 0 { details[key] = (.now, track) }
            }
        }
        try Task.checkCancellation()
        if !track.duration.isFinite { track.duration = 0 }
        return track
    }

    private func youtubeStream(_ id: String, quality: String, expectedDuration: Double) async throws -> PlaybackAsset {
        try Task.checkCancellation()
        guard id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { throw APIError.invalidResponse }
        let video = YouTube(videoID: id, methods: [.local])
        video.audioOnly = true
        let session = self.session
        let stream = try await video.firstPlayableAudioStream(dataSaver: quality == "data") { stream in
            try Task.checkCancellation()
            // `dur` is the actual media duration in the signed CDN URL, independent of a search label.
            // Reject unknown or combined recordings before downloading/playing any audio.
            guard Self.allowedMediaURL(stream.url), let actualDuration = Self.streamDuration(stream.url, formatDuration: stream.duration),
                  (expectedDuration <= 0 || Self.durationCompatible(expected: expectedDuration, actual: actualDuration)) else { return false }
            var request = URLRequest(url: stream.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
            request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
            do { return try await AudioHeaderProbe.check(request, configuration: session.configuration) }
            catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation(); return false }
        }
        guard let actualDuration = Self.streamDuration(stream.url, formatDuration: stream.duration) else { throw APIError.invalidResponse }
        let expires = URLComponents(url: stream.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "expire" })?.value.flatMap(Double.init)
        return PlaybackAsset(id: "youtube:" + id, path: stream.url.absoluteString, provider: "youtube", codec: "aac", bitrate: (stream.bitrate ?? 128000) / 1000, expiresAt: min(expires ?? Date().timeIntervalSince1970 + 1800, Date().timeIntervalSince1970 + 1800), duration: actualDuration)
    }

    private func youtubeSearch(_ query: String, videos: Bool = false) async throws -> [Track] {
        let locale = ListeningLocale.current
        let key = locale.cacheKey + "|" + (videos ? "videos|" : "songs|") + query.lowercased()
        if let (date, cached) = youtubeSearches[key], Date().timeIntervalSince(date) < 600 { return cached }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let version = "1." + formatter.string(from: .now) + ".01.00"
        let root = try await json("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", body: [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": version, "hl": locale.languageCode, "gl": locale.countryCode.uppercased()], "user": [:]],
            "query": query, "params": videos ? "EgWKAQIQAWoMEA4QChADEAQQCRAF" : "EgWKAQIIAWoMEA4QChADEAQQCRAF"
        ], headers: ["Origin": "https://music.youtube.com", "Referer": "https://music.youtube.com/", "X-Youtube-Client-Name": "67", "X-Youtube-Client-Version": version])
        let rows = Self.nodes(root, key: "musicResponsiveListItemRenderer")
        var seen = Set<String>()
        let result = rows.compactMap { row -> Track? in
            guard let id = Self.at(row, "playlistItemData.videoId") as? String ?? Self.firstString(row, key: "videoId"),
                  id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil, seen.insert(id).inserted else { return nil }
            let titleRuns = Self.at(row, "flexColumns.0.musicResponsiveListItemFlexColumnRenderer.text.runs") as? [JSON] ?? []
            let infoRuns = Self.at(row, "flexColumns.1.musicResponsiveListItemFlexColumnRenderer.text.runs") as? [JSON] ?? []
            let title = titleRuns.compactMap { $0["text"] as? String }.joined()
            guard !title.isEmpty else { return nil }
            let artistRuns = infoRuns.filter { Self.at($0, "navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType") as? String == "MUSIC_PAGE_TYPE_ARTIST" }
            let artist = artistRuns.compactMap { $0["text"] as? String }.joined(separator: ", ")
            let albumRun = infoRuns.first { Self.at($0, "navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType") as? String == "MUSIC_PAGE_TYPE_ALBUM" }
            let allText = infoRuns.compactMap { $0["text"] as? String } + Self.values(row["fixedColumns"] ?? [], key: "text")
            let time = allText.first { $0.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil } ?? "0:00"
            let duration = time.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
            let thumbs = Self.at(row, "thumbnail.musicThumbnailRenderer.thumbnail.thumbnails") as? [JSON]
            return Track(id: "youtube:" + id, title: title, artist: artist.isEmpty ? infoRuns.first?["text"] as? String ?? "" : artist, album: albumRun?["text"] as? String ?? "", duration: duration, artwork: thumbs?.last?["url"] as? String, source: "youtube")
        }
        if youtubeSearches.count > 60 { youtubeSearches.removeAll() }
        youtubeSearches[key] = (.now, result)
        return result
    }

    private func saavnSearch(_ query: String) async throws -> [Track] {
        let root = try await saavn("search.getResults", params: ["q": query, "p": "1", "n": "20"])
        return (root["results"] as? [JSON] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let more = row["more_info"] as? JSON ?? [:]
            let artist = row["primary_artists"] as? String ?? Self.at(more, "artistMap.primary_artists.0.name") as? String ?? row["subtitle"] as? String ?? ""
            let image = (row["image"] as? String)?.replacingOccurrences(of: #"\d+x\d+"#, with: "500x500", options: .regularExpression)
            return Track(id: "saavn:" + id, title: Self.unescape(row["song"] as? String ?? row["title"] as? String ?? ""), artist: Self.unescape(artist), album: Self.unescape(row["album"] as? String ?? more["album"] as? String ?? ""), duration: Self.number(row["duration"] ?? more["duration"]), artwork: image, source: "saavn")
        }
    }

    private func saavnStream(_ id: String, quality: String, duration: Double) async throws -> PlaybackAsset {
        guard id.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil else { throw APIError.invalidResponse }
        let root = try await saavn("song.getDetails", params: ["pids": id])
        let song = (root["songs"] as? [JSON])?.first ?? root[id] as? JSON ?? root.values.compactMap { $0 as? JSON }.first ?? [:]
        let more = song["more_info"] as? JSON ?? [:]
        let actualDuration = Self.number(song["duration"] ?? more["duration"])
        guard Self.durationCompatible(expected: duration, actual: actualDuration) else { throw APIError.invalidResponse }
        guard let encoded = song["encrypted_media_url"] as? String ?? more["encrypted_media_url"] as? String,
              let encrypted = Data(base64Encoded: encoded) else { throw APIError.invalidResponse }
        let key = Data("38346591".utf8)
        let capacity = encrypted.count + kCCBlockSizeDES
        var output = Data(count: capacity)
        var length = 0
        let status = key.withUnsafeBytes { keyBytes in
            encrypted.withUnsafeBytes { source in
                output.withUnsafeMutableBytes { target in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), keyBytes.baseAddress, kCCKeySizeDES, nil, source.baseAddress, encrypted.count, target.baseAddress, capacity, &length)
                }
            }
        }
        guard status == kCCSuccess else { throw APIError.invalidResponse }
        output.count = length
        guard let decoded = String(data: output, encoding: .utf8) else { throw APIError.invalidResponse }
        let high = String(describing: song["320kbps"] ?? more["320kbps"] ?? "false").lowercased() == "true"
        let bitrate = quality == "data" ? 96 : high ? 320 : 160
        let path = decoded.replacingOccurrences(of: #"_(?:12|48|96|160|320)\.mp4"#, with: "_\(bitrate).mp4", options: .regularExpression)
        guard let url = URL(string: path), Self.allowedMediaURL(url) else { throw APIError.invalidResponse }
        // A stale primary CDN link must fall through to the alternate source before playback starts.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = http.url, Self.allowedMediaURL(finalURL),
              !(http.mimeType ?? "").contains("text"), !(http.mimeType ?? "").contains("json") else { throw APIError.invalidResponse }
        return PlaybackAsset(id: "saavn:" + id, path: path, provider: "saavn", codec: "aac", bitrate: bitrate, expiresAt: Date().timeIntervalSince1970 + 1800, duration: actualDuration)
    }

    func lyrics(_ track: Track) async throws -> LyricsResponse {
        try await LyricsResolver(session: session).resolve(track)
    }

    static func lyricLookupTitles(_ track: Track) -> [String] {
        var seen = Set<String>()
        return [track.title, bilingualTitleBase(track.title)].filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func trace(_ message: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_TIMING"] == "1" { print("CATALOG_DIAGNOSTIC " + message) }
        #endif
    }

    private func appleSearch(_ query: String, entity: String = "song", limit: Int = 35, country: String? = nil) async throws -> [JSON] {
        let root = try await json("https://itunes.apple.com/search", query: ["term": query, "entity": entity, "country": country ?? ListeningLocale.current.countryCode, "limit": String(limit), "media": "music"])
        return root["results"] as? [JSON] ?? []
    }
    private func lookup(_ id: String, entity: String = "song", country: String? = nil) async throws -> [JSON] {
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { throw APIError.invalidResponse }
        let root = try await json("https://itunes.apple.com/lookup", query: ["id": id, "entity": entity, "country": country ?? ListeningLocale.current.countryCode, "limit": "100"])
        return root["results"] as? [JSON] ?? []
    }
    private func saavn(_ method: String, params: [String: String]) async throws -> JSON {
        var values = params
        values.merge(["__call": method, "_format": "json", "_marker": "0", "ctx": "web6dot0"]) { _, new in new }
        return try await json("https://www.jiosaavn.com/api.php", query: values)
    }
    private func json(_ address: String, query: [String: String] = [:], body: JSON? = nil, headers: [String: String] = [:]) async throws -> JSON {
        try Task.checkCancellation()
        guard var parts = URLComponents(string: address) else { throw APIError.invalidResponse }
        if !query.isEmpty { parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url, url.scheme == "https" else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = address.contains("youtubei/v1/search") ? 5 : 10
        request.setValue("KlyMusic/2.7 (iOS)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server("HTTP \(http.statusCode)") }
        guard data.count < 8_000_000, let object = try JSONSerialization.jsonObject(with: data) as? JSON else { throw APIError.invalidResponse }
        return object
    }

    private static func appleTrack(_ row: JSON) -> Track? {
        guard row["kind"] as? String == "song", let id = row["trackId"] as? NSNumber, let title = row["trackName"] as? String, let artist = row["artistName"] as? String else { return nil }
        return Track(id: "apple:" + id.stringValue, title: title, artist: artist, album: row["collectionName"] as? String ?? "", duration: number(row["trackTimeMillis"]) / 1000, artwork: art(row["artworkUrl100"] as? String), artistID: (row["artistId"] as? NSNumber)?.stringValue, albumID: (row["collectionId"] as? NSNumber)?.stringValue, explicit: row["trackExplicitness"] as? String == "explicit")
    }
    static func allowedMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return ["googlevideo.com", "saavncdn.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "ə", with: "e").replacingOccurrences(of: "Ə", with: "E").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression).split(separator: " ").joined(separator: " ")
    }
    static func canonical(_ value: String) -> String {
        let withoutFeatures = value.replacingOccurrences(of: #"(?:[\(\[]\s*|\s+)(?:feat(?:uring)?|ft)\.?\s+[^\)\]]+[\)\]]?\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        var result = normalized(withoutFeatures.replacingOccurrences(of: #"[\(\[]\s*from\b.*?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive]))
        let suffixes = [" official audio", " official music video", " official lyric video", " official video", " lyric video", " lyrics video", " official lyrics", " lyrics", " orijinal versiyon", " original version"]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes where result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return result
    }

    static func durationCompatible(expected: Double, actual: Double) -> Bool {
        guard expected.isFinite, actual.isFinite, expected > 0, actual > 0 else { return false }
        return abs(expected - actual) <= max(3, min(5, expected * 0.025))
    }

    static func mediaDuration(_ url: URL) -> Double? {
        guard allowedMediaURL(url), let host = url.host?.lowercased(), host == "googlevideo.com" || host.hasSuffix(".googlevideo.com"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let values = items.filter { $0.name == "dur" }
        guard values.count == 1, let value = values.first?.value, let seconds = Double(value), seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    static func streamDuration(_ url: URL, formatDuration: Double?) -> Double? {
        guard allowedMediaURL(url), let host = url.host?.lowercased(), host == "googlevideo.com" || host.hasSuffix(".googlevideo.com") else { return nil }
        let metadata = formatDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let durationFields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "dur" } ?? []
        if !durationFields.isEmpty {
            guard let signed = mediaDuration(url) else { return nil }
            if let metadata, !durationCompatible(expected: signed, actual: metadata) { return nil }
            return signed
        }
        return metadata
    }

    private static func transliteratedTitle(_ value: String) -> String {
        guard value.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil else { return canonical(value) }
        let phonetic = value.replacingOccurrences(of: "й", with: "y").replacingOccurrences(of: "Й", with: "Y")
        return canonical(phonetic.applyingTransform(.toLatin, reverse: false) ?? phonetic)
    }
    private static func bilingualTitleBase(_ value: String) -> String {
        guard let range = value.range(of: #"\s*[\(\[][^\)\]]+[\)\]]\s*$"#, options: .regularExpression) else { return value }
        let base = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let alias = String(value[range]).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]\n\t"))
        let baseCyrillic = base.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
        let aliasCyrillic = alias.range(of: #"\p{Cyrillic}"#, options: .regularExpression) != nil
        guard baseCyrillic != aliasCyrillic, !base.isEmpty,
              transliteratedTitle(base) == transliteratedTitle(alias) else { return value }
        return base
    }
    private static func identityTitle(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: #"\s*[\(\[]\s*(?:official(?: music)?(?: audio| video)?|official lyric video|lyrics?)\s*[\)\]]\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return transliteratedTitle(bilingualTitleBase(cleaned))
    }

    private static func creditedVideo(_ track: Track) -> (artists: Set<String>, title: String)? {
        // A collaboration may be uploaded by one credited artist, while another
        // catalogue lists the producer. Require explicit credits and a credited uploader.
        guard let separator = track.title.range(of: #"\s+[-–—]\s+"#, options: .regularExpression) else { return nil }
        let credits = artistIdentity(String(track.title[..<separator.lowerBound]))
        let uploader = artistIdentity(track.artist)
        guard !uploader.isEmpty, uploader.isSubset(of: credits) else { return nil }
        let title = identityTitle(String(track.title[separator.upperBound...]))
        return title.isEmpty ? nil : (credits, title)
    }

    private static func recordingTitle(_ track: Track) -> String {
        if let video = creditedVideo(track) { return video.title }
        let title = identityTitle(track.title)
        let artists = artistIdentity(track.artist)
        let words = title.split(separator: " ")
        if artists.count == 1, words.count > 1 {
            for count in 1..<words.count where artists.contains(words.prefix(count).joined()) {
                return words.dropFirst(count).joined(separator: " ")
            }
        }
        return title
    }

    private static func artistIdentity(_ artist: String) -> Set<String> {
        let value = artist.replacingOccurrences(of: #"\s*(?:,|&|\b(?:featuring|feat|ft)\b\.?)\s*"#, with: "|", options: [.regularExpression, .caseInsensitive])
        return Set(value.split(separator: "|").map { component in
            var name = normalized(String(component))
            for suffix in [" topic", " vevo", " official"] where name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
            // Explicit credited-name spellings, never a fuzzy or missing-artist match.
            let aliases = ["Betsy": ["Betsy", "Бэтси", "Бетси"], "Maria Iankovskaia": ["Maria Iankovskaia", "Maria Yankovskaya", "Mariya Yankovskaya", "Мария Янковская"]]
            for (identity, spellings) in aliases where spellings.contains(where: { normalized($0) == name }) { name = normalized(identity) }
            return name.replacingOccurrences(of: " ", with: "")
        }.filter { !$0.isEmpty })
    }

    private static func recordingArtists(_ track: Track) -> Set<String> {
        var result = artistIdentity(track.artist)
        let pattern = #"(?:[\(\[]\s*|\s+)(?:feat(?:uring)?|ft)\.?\s+([^\)\]]+)[\)\]]?\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: track.title, range: NSRange(track.title.startIndex..., in: track.title)),
           let range = Range(match.range(at: 1), in: track.title) {
            result.formUnion(artistIdentity(String(track.title[range])))
        }
        return result
    }

    static func sameRecordingIdentity(_ requested: Track, _ candidate: Track) -> Bool {
        guard !recordingTitle(requested).isEmpty, recordingTitle(requested) == recordingTitle(candidate) else { return false }
        let requestedArtists = recordingArtists(requested)
        let candidateArtists = recordingArtists(candidate)
        guard !requestedArtists.isEmpty else { return false }
        if requestedArtists == candidateArtists { return true }
        if let video = creditedVideo(candidate), requestedArtists.isSubset(of: video.artists) { return true }
        return false
    }

    static func match(_ requested: Track, _ candidate: Track) -> Double {
        guard sameRecordingIdentity(requested, candidate),
              durationCompatible(expected: requested.duration, actual: candidate.duration) else { return 0 }
        // Title/artist identity must be exact after decoration removal; duration only ranks valid copies.
        return 0.9 + 0.1 * max(0, 1 - abs(requested.duration - candidate.duration) / 5)
    }
    private static func art(_ url: String?) -> String? {
        url?.replacingOccurrences(of: #"\d+x\d+(?:bb)?"#, with: "600x600bb", options: .regularExpression)
            .replacingOccurrences(of: "{w}", with: "1000").replacingOccurrences(of: "{h}", with: "1000").replacingOccurrences(of: "{f}", with: "jpg").replacingOccurrences(of: "{c}", with: "bb")
    }
    private static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&#39;", with: "'")
    }
    private static func at(_ object: Any?, _ path: String) -> Any? {
        path.split(separator: ".").reduce(object) { value, key in
            if let array = value as? [Any], let index = Int(key), array.indices.contains(index) { return array[index] }
            return (value as? JSON)?[String(key)]
        }
    }
    private static func nodes(_ object: Any, key: String) -> [JSON] {
        if let dictionary = object as? JSON {
            return (dictionary[key] as? JSON).map { [$0] } ?? dictionary.values.flatMap { nodes($0, key: key) }
        }
        return (object as? [Any] ?? []).flatMap { nodes($0, key: key) }
    }
    private static func firstString(_ object: Any, key: String) -> String? { values(object, key: key).first }
    private static func values(_ object: Any, key: String) -> [String] {
        if let dictionary = object as? JSON {
            return (dictionary[key] as? String).map { [$0] } ?? dictionary.values.flatMap { values($0, key: key) }
        }
        return (object as? [Any] ?? []).flatMap { values($0, key: key) }
    }
}

/// Public lyric sources; preserve real timestamps and never synthesize timing for plain text.
struct LyricsResolver {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let fetch: Fetch
    init(session: URLSession) {
        fetch = { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, response)
        }
    }
    init(fetch: @escaping Fetch) { self.fetch = fetch }

    private struct Result {
        let lyrics: LyricsResponse?
        let error: Error?
    }
    func resolve(_ track: Track) async throws -> LyricsResponse {
        try Task.checkCancellation()
        guard !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return LyricsResponse(instrumental: false) }
        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask { try await attempt { try await exact(track) } }
            group.addTask {
                try await Task.sleep(for: .milliseconds(250))
                return try await attempt { try await search(track) }
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(500))
                return try await attempt { try await alternative(track) }
            }
            defer { group.cancelAll() }
            var plain: LyricsResponse?, instrumental: LyricsResponse?, failure: Error?
            while let result = try await group.next() {
                try Task.checkCancellation()
                if let lyrics = result.lyrics {
                    if !lyrics.lines.isEmpty { return lyrics }
                    if let text = lyrics.plain, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { plain = plain ?? lyrics }
                    else if lyrics.instrumental { instrumental = lyrics }
                }
                failure = failure ?? result.error
            }
            if let plain { return plain }
            if let instrumental { return instrumental }
            if let failure { throw failure }
            return LyricsResponse(instrumental: false)
        }
    }
    private func attempt(_ operation: () async throws -> LyricsResponse?) async throws -> Result {
        do { return Result(lyrics: try await operation(), error: nil) }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation(); return Result(lyrics: nil, error: error) }
    }
    private func exact(_ track: Track) async throws -> LyricsResponse? {
        var params = ["track_name": track.title, "artist_name": track.artist]
        if !track.album.isEmpty { params["album_name"] = track.album }
        if track.duration.isFinite, track.duration > 0 { params["duration"] = String(Int(track.duration.rounded())) }
        guard let data = try await request("https://lrclib.net/api/get", query: params) else { return nil }
        return try JSONDecoder().decode(LRCLyricsRecord.self, from: data).matched(to: track)
    }
    private func search(_ track: Track) async throws -> LyricsResponse? {
        // Search by title so a reissue album or collaboration spelling cannot hide the result.
        // Every row is checked locally against title, credited artists and recording duration.
        var fallback: LyricsResponse?
        for title in NativeCatalog.lyricLookupTitles(track).reversed() {
            guard let data = try await request("https://lrclib.net/api/search", query: ["track_name": title]) else { continue }
            let records = try JSONDecoder().decode([LRCLyricsRecord].self, from: data)
            let matches = records.compactMap { record -> (LRCLyricsRecord, LyricsResponse)? in
                guard let value = record.matched(to: track) else { return nil }
                return (record, value)
            }.sorted { first, second in
                if first.1.lines.isEmpty != second.1.lines.isEmpty { return !first.1.lines.isEmpty }
                let a = NativeCatalog.normalized(first.0.albumName ?? "") == NativeCatalog.normalized(track.album)
                let b = NativeCatalog.normalized(second.0.albumName ?? "") == NativeCatalog.normalized(track.album)
                if a != b { return a }
                return abs((first.0.duration ?? 0) - track.duration) < abs((second.0.duration ?? 0) - track.duration)
            }
            if let timed = matches.first(where: { !$0.1.lines.isEmpty }) { return timed.1 }
            if let value = matches.first?.1 { fallback = fallback ?? value }
        }
        return fallback
    }
    private func alternative(_ track: Track) async throws -> LyricsResponse? {
        // This source has no timestamps or identity metadata: query the full credited artist exactly.
        for title in NativeCatalog.lyricLookupTitles(track) {
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
            guard let artist = track.artist.addingPercentEncoding(withAllowedCharacters: allowed),
                  let title = title.addingPercentEncoding(withAllowedCharacters: allowed),
                  let data = try await request("https://api.lyrics.ovh/v1/" + artist + "/" + title) else { continue }
            struct Response: Decodable { let lyrics: String? }
            let text = try JSONDecoder().decode(Response.self, from: data).lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty { return LyricsResponse(plain: text, instrumental: false) }
        }
        return nil
    }
    private func request(_ address: String, query: [String: String] = [:]) async throws -> Data? {
        try Task.checkCancellation()
        guard var components = URLComponents(string: address), components.scheme == "https",
              ["lrclib.net", "api.lyrics.ovh"].contains(components.host ?? "") else { throw APIError.invalidResponse }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("KlyMusic/2.12 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await fetch(request)
        try Task.checkCancellation()
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else { throw APIError.server("HTTP \(response.statusCode)") }
        guard data.count <= 2_000_000 else { throw APIError.invalidResponse }
        return data
    }
}

struct LRCLyricsRecord: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?

    func matched(to requested: Track) -> LyricsResponse? {
        guard let title = trackName, let artist = artistName else { return nil }
        let candidate = Track(id: "lyrics", title: title, artist: artist, album: albumName ?? "", duration: duration ?? 0)
        guard NativeCatalog.sameRecordingIdentity(requested, candidate) else { return nil }
        let knownRequested = requested.duration.isFinite && requested.duration > 0
        if knownRequested {
            guard NativeCatalog.durationCompatible(expected: requested.duration, actual: candidate.duration) else { return nil }
        }
        let plain = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let synced = syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = LyricLine.parse(synced ?? "")
        let sameAlbum = !requested.album.isEmpty && NativeCatalog.normalized(requested.album) == NativeCatalog.normalized(candidate.album)
        let bounded = candidate.duration.isFinite && candidate.duration > 0 && parsed.allSatisfy { $0.time >= 0 && $0.time <= candidate.duration + 5 }
        let timed = !parsed.isEmpty && bounded && (knownRequested || sameAlbum)
        let text = (plain?.isEmpty == false ? plain : (!parsed.isEmpty ? parsed.map(\.text).joined(separator: "\n") : nil))
        let response = LyricsResponse(plain: text, synced: timed ? synced : nil, instrumental: instrumental == true && text == nil && !timed)
        return response.hasContent ? response : nil
    }
}
