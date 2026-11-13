import XCTest
import Combine
import SwiftData
import AVFoundation
import MediaPlayer
import UIKit
@testable import KlyMusic

final class CoreTests: XCTestCase {
    func testLiveCatalogMatchingDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_MATCHING"] == "1" else { throw XCTSkip("Live catalog matching is opt-in") }
        let catalog = NativeCatalog()
        let response: HomeResponse
        do { response = try await catalog.home() }
        catch { throw XCTSkip("Live catalog unavailable: \(error.localizedDescription)") }
        var artists = Set<String>()
        let tracks = Array(response.sections.flatMap(\.tracks).filter { artists.insert(NativeCatalog.normalized($0.artist)).inserted }.prefix(6))
        guard !tracks.isEmpty else { throw XCTSkip("Live catalog has no sample") }
        var matched = 0
        for track in tracks {
            do {
                let copies = try await catalog.matchingDiagnostic(track)
                XCTAssertTrue(copies.allSatisfy { NativeCatalog.sameRecordingIdentity(track, $0) })
                if !copies.isEmpty { matched += 1 }
                print("CATALOG_MATCH_SAMPLE id=\(track.id) artist=\(track.artist) matched=\(!copies.isEmpty) candidates=\(copies.count) audio_verified=false")
            } catch { print("CATALOG_MATCH_SAMPLE id=\(track.id) source_error=\(error.localizedDescription) audio_verified=false") }
        }
        print("CATALOG_MATCH_SUMMARY sampled=\(tracks.count) matched=\(matched) audible_verified=0")
    }

    func testResolverTriesPlayableCopiesBeyondFirstThreeAndReusesVerifiedStream() async throws {
        let track = Track(id: "test:general-" + UUID().uuidString, title: "Unit Song", artist: "Unit Artist", duration: 180)
        CatalogResponseProtocol.handler = { _ in Self.catalogRows(["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc", "ddddddddddd"], title: track.title, artist: track.artist) }
        defer { CatalogResponseProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CatalogResponseProtocol.self]
        let calls = PlaybackCallRecorder()
        let catalog = NativeCatalog(session: URLSession(configuration: configuration)) { candidate, _, _ in
            await calls.record(candidate.id)
            guard candidate.id == "youtube:ddddddddddd" else { throw PlaybackFailure.unavailable }
            return Self.resolverAsset(candidate.id)
        }
        let resolved = try await catalog.resolve(track, provider: "youtube", quality: "data")
        XCTAssertEqual(resolved.id, "youtube:ddddddddddd")
        let first = await calls.values
        XCTAssertTrue(first.contains("youtube:ddddddddddd"), "Do not abandon matching copies after three unavailable candidates")
        _ = try await catalog.resolve(track, provider: "youtube", quality: "data")
        let cached = await calls.values
        XCTAssertEqual(cached.filter { $0 == resolved.id }.count, 1)
        await catalog.invalidatePlayback()
        _ = try await catalog.resolve(track, provider: "youtube", quality: "data")
        let renewed = await calls.values
        XCTAssertEqual(renewed.filter { $0 == resolved.id }.count, 2, "A failed playback must be able to renew a signed media URL")
    }

    func testResolverContinuesGeneralQueriesAfterFirstMatchedCopyFails() async throws {
        let track = Track(id: "test:alternate-query-" + UUID().uuidString, title: "Unit Song", artist: "Unit Artist", duration: 180)
        let queries = NativeCatalog.candidateQueries(track)
        XCTAssertGreaterThanOrEqual(queries.count, 2)
        CatalogResponseProtocol.handler = { request in
            let query = CatalogResponseProtocol.query(request)
            let id = query == queries.first ? "aaaaaaaaaaa" : "bbbbbbbbbbb"
            return Self.catalogRows([id], title: track.title, artist: track.artist)
        }
        defer { CatalogResponseProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CatalogResponseProtocol.self]
        let catalog = NativeCatalog(session: URLSession(configuration: configuration)) { candidate, _, _ in
            if candidate.id == "youtube:aaaaaaaaaaa" { throw PlaybackFailure.unavailable }
            return Self.resolverAsset(candidate.id)
        }
        let resolved = try await catalog.resolve(track, provider: "youtube", quality: "data")
        XCTAssertEqual(resolved.id, "youtube:bbbbbbbbbbb")
    }

    func testResolverDistinguishesProviderAuthenticationFromNoMatch() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CatalogResponseProtocol.self]
        let track = Track(id: "test:reasons-" + UUID().uuidString, title: "Unit Song", artist: "Unit Artist", duration: 180)
        CatalogResponseProtocol.handler = { _ in Self.catalogRows(["aaaaaaaaaaa"], title: track.title, artist: track.artist) }
        defer { CatalogResponseProtocol.handler = nil }
        let blocked = NativeCatalog(session: URLSession(configuration: configuration)) { _, _, _ in throw PlaybackFailure.authenticationRequired }
        do { _ = try await blocked.resolve(track, provider: "youtube"); XCTFail("Blocked source cannot become a successful playback") }
        catch let error as PlaybackFailure { XCTAssertEqual(error, .authenticationRequired) }
        CatalogResponseProtocol.handler = { _ in Self.catalogRows([], title: track.title, artist: track.artist) }
        let missing = NativeCatalog(session: URLSession(configuration: configuration)) { _, _, _ in XCTFail("No candidate should reach media extraction"); throw PlaybackFailure.invalidMedia }
        do { _ = try await missing.resolve(track, provider: "youtube"); XCTFail("Expected missing recording") }
        catch let error as PlaybackFailure { XCTAssertEqual(error, .noMatch) }
    }

    func testPlaybackRacePreservesActionableProviderFailureAcrossEmptyFallbacks() async {
        do {
            let _: String = try await PlaybackRace.first([
                { throw PlaybackFailure.authenticationRequired },
                { try await Task.sleep(for: .milliseconds(10)); throw PlaybackFailure.noMatch }
            ])
            XCTFail("Expected provider failure")
        } catch let error as PlaybackFailure { XCTAssertEqual(error, .authenticationRequired) }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testEmptyPlaybackRaceReportsNoMatch() async {
        do {
            let _: String = try await PlaybackRace.first([])
            XCTFail("An empty candidate list cannot produce a recording")
        } catch let error as PlaybackFailure { XCTAssertEqual(error, .noMatch) }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testYouTubeSearchParserRetainsUnlabelledCollaborationCredits() {
        let root = Self.catalogRows(["aaaaaaaaaaa"], title: "Unit Song", artist: "First Artist & Second Artist", linkedArtists: false)
        let result = NativeCatalog.youtubeTracks(root)
        XCTAssertEqual(result.first?.artist, "First Artist & Second Artist")
        XCTAssertEqual(result.first?.duration, 180)
    }

    private static func resolverAsset(_ id: String) -> PlaybackAsset {
        PlaybackAsset(id: id, path: "https://rr1.googlevideo.com/audio?dur=180", provider: "youtube", codec: "aac", bitrate: 48,
                      expiresAt: Date().timeIntervalSince1970 + 1800, duration: 180)
    }
    private static func catalogRows(_ ids: [String], title: String, artist: String, linkedArtists: Bool = true) -> [String: Any] {
        var artistRun: [String: Any] = ["text": artist]
        if linkedArtists { artistRun["navigationEndpoint"] = ["browseEndpoint": ["browseId": "UC_unit_artist"]] }
        let rows = ids.map { id -> [String: Any] in
            let titleColumn: [String: Any] = ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": title]]]]]
            let infoColumn: [String: Any] = ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [artistRun, ["text": " • "], ["text": "3:00"]]]]]
            return ["musicResponsiveListItemRenderer": ["playlistItemData": ["videoId": id], "flexColumns": [titleColumn, infoColumn]]]
        }
        return ["contents": rows]
    }

    func testLyricsDataSaverUsesOnlyExactRequestWhenTimedLyricsExist() async throws {
        let resolver = LyricsResolver { request in
            let url = request.url!
            XCTAssertEqual(url.path, "/api/get", "Data saver must not download extra search/provider payloads for a successful timed match")
            let row: [String: Any] = ["trackName": "Gece", "artistName": "Test Artist", "duration": 180, "syncedLyrics": "[00:01]Test verse"]
            return (try JSONSerialization.data(withJSONObject: row), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let response = try await resolver.resolve(Track(id: "test:single-lyrics-request", title: "Gece", artist: "Test Artist", duration: 180))
        XCTAssertEqual(response.lines.first?.text, "Test verse")
    }

    func testLyricsSearchFindsSameRecordingFromDifferentAlbumAfterExactMiss() async throws {
        let track = Track(id: "test:lyrics", title: "Gece", artist: "Test Artist", album: "Reissue", duration: 180)
        let resolver = LyricsResolver { request in
            let url = try XCTUnwrap(request.url)
            let object: Any
            var status = 200
            if url.path == "/api/get" { status = 404; object = [String: String]() }
            else if url.path == "/api/search" {
                object = [["trackName": "Gece", "artistName": "Test Artist", "albumName": "Original", "duration": 181, "plainLyrics": "Test verse", "syncedLyrics": "[00:01.00]Test verse", "instrumental": false]]
            } else { status = 404; object = [String: String]() }
            return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await resolver.resolve(track)
        XCTAssertEqual(result.lines.first?.text, "Test verse")
        XCTAssertEqual(result.lines.first?.time, 1)
    }

    func testLyricsMatchingRejectsDifferentArtistsVersionsAndDurations() throws {
        let requested = Track(id: "test:words", title: "Gece", artist: "Test Artist", duration: 180)
        func record(_ title: String, _ artist: String, _ duration: Double) throws -> LRCLyricsRecord {
            let object: [String: Any] = ["trackName": title, "artistName": artist, "duration": duration, "syncedLyrics": "[00:01]Test verse", "plainLyrics": "Test verse"]
            return try JSONDecoder().decode(LRCLyricsRecord.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertNotNil(try record("Gece", "Test Artist", 181).matched(to: requested))
        for (title, artist, duration) in [("Gece Remix", "Test Artist", 180.0), ("Gece", "Other Artist", 180.0), ("Gece", "Test Artist", 350.0), ("Gece", "Test Artist", 0.0)] {
            XCTAssertNil(try record(title, artist, duration).matched(to: requested))
        }
    }

    func testLyricsOVHFallbackHandlesUnicodePathAndDoesNotInventTiming() async throws {
        let track = Track(id: "test:ovh", title: "Şımarık / Test", artist: "Tarkan / Test", duration: 190)
        let resolver = LyricsResolver { request in
            let url = try XCTUnwrap(request.url)
            let isAlternative = url.host == "api.lyrics.ovh"
            if isAlternative {
                let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
                XCTAssertTrue(encoded.contains("%2F"), "Each path component must escape slash")
                XCTAssertTrue(encoded.contains("%C5"), "Turkish characters must be percent encoded")
            }
            let object: Any = isAlternative ? ["lyrics": "  Test verse\nNext verse  "] : (url.path == "/api/search" ? [] : [String: String]())
            let status = isAlternative || url.path == "/api/search" ? 200 : 404
            return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await resolver.resolve(track)
        XCTAssertEqual(result.plain, "Test verse\nNext verse")
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertNil(result.synced)
        XCTAssertFalse(result.instrumental)
    }

    func testLyricsPreferSyncedSearchOverExactPlainText() async throws {
        let resolver = LyricsResolver { request in
            let url = request.url!
            let base: [String: Any] = ["trackName": "Gece", "artistName": "Test Artist", "duration": 180, "plainLyrics": "Plain exact"]
            var object: Any = base
            if url.path == "/api/search" {
                var row = base; row["syncedLyrics"] = "[00:02]Timed match"; object = [row]
            } else if url.host == "api.lyrics.ovh" { object = ["lyrics": "Other plain"] }
            return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await resolver.resolve(Track(id: "test:priority", title: "Gece", artist: "Test Artist", duration: 180))
        XCTAssertEqual(result.lines.first?.text, "Timed match")
    }

    func testLyricsProviderFailureCanFallBackAndMissingIsDifferentFromFailure() async throws {
        let track = Track(id: "test:availability", title: "Gece", artist: "Test Artist", duration: 180)
        let fallback = LyricsResolver { request in
            let url = request.url!
            if url.host == "lrclib.net" { throw URLError(.timedOut) }
            return (Data(#"{"lyrics":"Fallback verse"}"#.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let recovered = try await fallback.resolve(track)
        XCTAssertEqual(recovered.plain, "Fallback verse")
        let missing = LyricsResolver { request in (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!) }
        let empty = try await missing.resolve(track)
        XCTAssertFalse(empty.hasContent)
        let failed = LyricsResolver { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await failed.resolve(track); XCTFail("Unavailable sources must remain retryable errors") } catch is URLError { }
    }

    func testLyricsUnknownDurationAndInvalidTimingsRemainPlain() throws {
        func decode(_ object: [String: Any]) throws -> LRCLyricsRecord {
            try JSONDecoder().decode(LRCLyricsRecord.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let requested = Track(id: "test:unknown", title: "Gece", artist: "Test Artist")
        let value = try XCTUnwrap(decode(["trackName": "Gece", "artistName": "Test Artist", "duration": 180, "syncedLyrics": "[00:02]Test verse"]).matched(to: requested))
        XCTAssertEqual(value.plain, "Test verse")
        XCTAssertTrue(value.lines.isEmpty)
        let malformed = try decode(["trackName": "Gece", "artistName": "Test Artist", "duration": 180, "syncedLyrics": "not timed", "plainLyrics": "   "])
        XCTAssertNil(malformed.matched(to: requested))
        let overflow = try XCTUnwrap(decode(["trackName": "Gece", "artistName": "Test Artist", "duration": 180, "syncedLyrics": "[99:00]Test verse"]).matched(to: Track(id: "test:bounded", title: "Gece", artist: "Test Artist", duration: 180)))
        XCTAssertTrue(overflow.lines.isEmpty)
        XCTAssertEqual(overflow.plain, "Test verse")
    }

    func testLyricsCancellationStopsPendingLookupAndDelayedFallbacks() async throws {
        let started = expectation(description: "Exact lyric lookup started")
        let resolver = LyricsResolver { request in
            XCTAssertEqual(request.url?.path, "/api/get", "Cancelled lookup must not start delayed fallbacks")
            started.fulfill()
            try await Task.sleep(for: .seconds(30))
            throw URLError(.timedOut)
        }
        let task = Task { try await resolver.resolve(Track(id: "test:cancel-lyrics", title: "Gece", artist: "Test Artist", duration: 180)) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }

    func testPublicLyricsSourcesDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_LYRICS"] == "1" else { throw XCTSkip("Live lyric diagnostic is opt-in") }
        do {
            let result = try await LyricsResolver(session: URLSession(configuration: .ephemeral)).resolve(Track(id: "lyrics:diagnostic", title: "Şımarık", artist: "Tarkan", duration: 191))
            guard result.hasContent else { throw APIError.invalidResponse }
            print("LIVE_LYRICS matched=true timed=\(!result.lines.isEmpty) plain_characters=\(result.plain?.count ?? 0) (no lyric body logged)")
        } catch {
            throw XCTSkip("Live lyric provider unavailable from CI: \(error.localizedDescription)")
        }
    }

    func testBilingualSigmaBoyMatchesLatinAndCyrillicCreditsWithoutAcceptingOtherVersions() {
        let original = Track(id: "apple:sigma", title: "Sigma Boy (Сигма Бой)", artist: "Betsy & Maria Iankovskaia", duration: 161)
        let latin = Track(id: "youtube:abcdefghijk", title: "Sigma Boy", artist: "Betsy, Maria Yankovskaya", duration: 162)
        let cyrillic = Track(id: "youtube:abcdefghijk", title: "Сигма Бой", artist: "Бэтси, Мария Янковская", duration: 162)
        let decorated = Track(id: "youtube:abcdefghijk", title: "Sigma Boy (Сигма Бой) (Official Audio)", artist: latin.artist, duration: 162)
        for copy in [latin, cyrillic, decorated] { XCTAssertGreaterThan(NativeCatalog.match(original, copy), 0.9) }
        for title in ["Sigma Boy (Techno Remix)", "Sigma Boy (Sped Up)", "Sigma Boy (Live)", "Sigma Boy (Сигма Бой) Remix"] {
            var other = latin; other.title = title
            XCTAssertEqual(NativeCatalog.match(original, other), 0, title)
        }
        var cover = latin; cover.artist = "Other Artist"
        XCTAssertEqual(NativeCatalog.match(original, cover), 0)
        cover = latin; cover.artist = "Betsy"
        XCTAssertEqual(NativeCatalog.match(original, cover), 0, "Missing credited collaborators must not be ignored")
        XCTAssertEqual(NativeCatalog.candidateQueries(original).first, "Betsy & Maria Iankovskaia sigma boy")
        XCTAssertTrue(NativeCatalog.candidateQueries(original).contains("sigma boy"))
        XCTAssertGreaterThanOrEqual(NativeCatalog.candidateQueries(latin).count, 2)
    }

    func testDirectYouTubeIDCanEstablishDurationFromVerifiedMedia() {
        let direct = Track(id: "youtube:abcdefghijk", title: "Track", artist: "Artist")
        XCTAssertTrue(NativeCatalog.validResolvedDuration(direct, candidate: direct, actual: 161))
        XCTAssertFalse(NativeCatalog.validResolvedDuration(direct, candidate: direct, actual: 0))
        var other = direct; other.id = "youtube:other123456"
        XCTAssertFalse(NativeCatalog.validResolvedDuration(direct, candidate: other, actual: 161))
        var catalog = direct; catalog.id = "apple:1"
        XCTAssertFalse(NativeCatalog.validResolvedDuration(catalog, candidate: direct, actual: 161))
        catalog.duration = 161
        XCTAssertFalse(NativeCatalog.validResolvedDuration(catalog, candidate: direct, actual: 320))
    }

    func testVideoWithoutSearchDurationRequiresIdentityAndKnownRequestedDuration() {
        let requested = Track(id: "apple:video", title: "Kuzu Kuzu", artist: "Tarkan", duration: 220)
        let candidate = Track(id: "youtube:abcdefghijk", title: "Kuzu Kuzu", artist: "Tarkan")
        XCTAssertTrue(NativeCatalog.validCandidate(requested, candidate, videosOnly: true))
        XCTAssertFalse(NativeCatalog.validCandidate(requested, candidate, videosOnly: false))
        var unknown = requested; unknown.duration = 0
        XCTAssertFalse(NativeCatalog.validCandidate(unknown, candidate, videosOnly: true))
        var wrong = candidate; wrong.artist = "Unrelated"
        XCTAssertFalse(NativeCatalog.validCandidate(requested, wrong, videosOnly: true))
        wrong = candidate; wrong.duration = 440
        XCTAssertFalse(NativeCatalog.validCandidate(requested, wrong, videosOnly: true))
        wrong.duration = .nan
        XCTAssertFalse(NativeCatalog.validCandidate(requested, wrong, videosOnly: true))
    }

    func testSharedMatchSearchCancellationKeepsOtherWaiterAlive() async throws {
        let pool = MatchRequestPool()
        let gate = PlaybackResolutionGate()
        let first = Task { try await pool.value(for: "same") {
            _ = await gate.wait("release")
            return [Track(id: "same", title: "Same", artist: "Test")]
        } }
        while await pool.waiterCount(for: "same") < 1 { await Task.yield() }
        let second = Task { try await pool.value(for: "same") {
            XCTFail("Matching search must be coalesced")
            return []
        } }
        while await pool.waiterCount(for: "same") < 2 { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled waiter must leave immediately") } catch is CancellationError { }
        await gate.complete("release", asset: Self.cacheAsset("ready"))
        let rows = try await second.value
        XCTAssertEqual(rows.map(\.id), ["same"])
    }

    func testPlaybackWinnerDoesNotWaitForLosingMetadataSearch() async throws {
        let pool = MatchRequestPool()
        let started = Date()
        let winner = try await PlaybackRace.first([
            { @Sendable () async throws -> String in
                _ = try await pool.value(for: "slow") {
                    try await Task.sleep(for: .seconds(30))
                    return []
                }
                return "slow"
            },
            { @Sendable () async throws -> String in
                while await pool.waiterCount(for: "slow") == 0 { await Task.yield() }
                return "ready"
            }
        ])
        XCTAssertEqual(winner, "ready")
        let elapsed = Date().timeIntervalSince(started) * 1000
        print("MATCH_RACE_CONTROL_MS=\(elapsed) (synthetic cancellation control, not network or audible latency)")
        XCTAssertLessThan(elapsed, 2000)
        let remaining = await pool.waiterCount(for: "slow")
        XCTAssertEqual(remaining, 0)
    }

    func testReportedSigmaBoyResolutionDiagnostic() async throws {
        try await reportedPlaybackDiagnostic(Track(id: "apple:1833553551", title: "Sigma Boy (Сигма Бой)", artist: "Betsy & Maria Iankovskaia", duration: 134.4))
    }

    func testLocalLibrarySearchMatchesWordsInAnyOrderAndSeparatesAlbumsByArtist() throws {
        let first = Track(id: "first", title: "Kuzu Kuzu", artist: "Tarkan", album: "Karma")
        let second = Track(id: "second", title: "Diğer", artist: "Tarkan", album: "Karma")
        let other = Track(id: "other", title: "Şarkı", artist: "Başka Sanatçı", album: "Karma")
        let tracks = [first, second, other]
        let songs = LibrarySearchResults(tracks: tracks, playlists: [], query: "kuzu tarkan")
        XCTAssertEqual(songs.response.tracks.map(\.id), [first.id])
        let albums = LibrarySearchResults(tracks: tracks, playlists: [], query: "karma")
        XCTAssertEqual(albums.response.albums.count, 2, "Equal titles from different artists must remain separate")
        let tarkanAlbum = try XCTUnwrap(albums.response.albums.first { $0.artist == "Tarkan" })
        XCTAssertEqual(albums.tracks(in: tarkanAlbum).map(\.id), [first.id, second.id])
        let artists = LibrarySearchResults(tracks: tracks, playlists: [], query: "tarkan")
        XCTAssertEqual(artists.response.artists.count, 1)
        XCTAssertEqual(artists.tracks(by: try XCTUnwrap(artists.response.artists.first)).map(\.id), [first.id, second.id])
    }

    @MainActor func testLocalLibrarySearchFindsListsAndDoesNotMatchBlankQuery() {
        let playlist = SavedPlaylist(name: "Yaz Yolculuğu")
        let results = LibrarySearchResults(tracks: [], playlists: [playlist], query: "yolculugu yaz")
        XCTAssertEqual(results.playlists.map(\.id), [playlist.id])
        let blank = LibrarySearchResults(tracks: [Track(id: "a", title: "A", artist: "Test", album: "Album")], playlists: [playlist], query: "  ")
        XCTAssertTrue(blank.response.tracks.isEmpty)
        XCTAssertTrue(blank.response.albums.isEmpty)
        XCTAssertTrue(blank.response.artists.isEmpty)
        XCTAssertTrue(blank.playlists.isEmpty)
    }

    @MainActor func testRestoreUnknownDatesDoNotReplaceKnownDatesAndExactDatesImproveLegacyRecords() throws {
        let suite = "LibraryDateMerge-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let track = Track(id: "dated", title: "Dated", artist: "Test")
        let store = LibraryStore(context: context, insertionDefaults: defaults, now: { Date(timeIntervalSince1970: 500) })
        store.toggleFavorite(track)
        func data(_ date: Date) throws -> Data {
            try JSONEncoder().encode(LibraryBackup(tracks: [.init(track: track, favorite: true, lastPlayed: nil, playCount: 0, addedAt: date)], playlists: [], settings: [:]))
        }
        try store.restore(data(.distantPast))
        XCTAssertEqual(store.recentlyAddedCollections.first?.addedAt, Date(timeIntervalSince1970: 500))
        defaults.set([track.id: Date.distantPast.timeIntervalSince1970 - 0.001], forKey: "savedTrackAddedDates-v1")
        try store.restore(data(Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(store.recentlyAddedCollections.first?.addedAt, Date(timeIntervalSince1970: 300))
    }

    func testLocalArtistSearchKeepsOneIdentityAcrossCollaborationDisplayNames() throws {
        let solo = Track(id: "solo", title: "A", artist: "BLOK3", artistID: "same-artist")
        let duet = Track(id: "duet", title: "B", artist: "BLOK3 & Poizi", artistID: "same-artist")
        let results = LibrarySearchResults(tracks: [solo, duet], playlists: [], query: "blok3")
        XCTAssertEqual(results.response.artists.map(\.id), ["same-artist"])
        XCTAssertEqual(results.tracks(by: try XCTUnwrap(results.response.artists.first)).map(\.id), [solo.id, duet.id])
    }

    func testHomeShelvesRemoveReissuesAndRecentSongsWithoutHidingDifferentVersions() {
        let original = Track(id: "apple:1", title: "Kuzu Kuzu", artist: "Tarkan")
        let reissue = Track(id: "apple:2", title: "Kuzu Kuzu", artist: "Tarkan")
        let remix = Track(id: "apple:3", title: "Kuzu Kuzu Remix", artist: "Tarkan")
        let other = Track(id: "apple:4", title: "Dudu", artist: "Tarkan")
        let sections = [HomeSection(id: "a", title: "A", subtitle: "", tracks: [original, remix]), HomeSection(id: "b", title: "B", subtitle: "", tracks: [reissue, other])]
        let feed = HomeFeed.distinct(sections)
        XCTAssertEqual(feed.flatMap(\.tracks).map(\.id), [original.id, remix.id, other.id])
        XCTAssertEqual(HomeFeed.distinct(sections, excluding: [reissue]).flatMap(\.tracks).map(\.id), [remix.id, other.id])
    }

    func testEditorialCategoriesUseGenreArtworkAndRejectUnsupportedServices() throws {
        func item(_ id: String, _ title: String) -> [String: Any] {
            ["title": title, "contentDescriptor": ["identifiers": ["storeAdamID": id]], "artwork": ["dictionary": ["url": "https://is1-ssl.mzstatic.com/image/thumb/Features/test/{w}x{h}{c}.{f}"]]]
        }
        let items = [item("1", "Pop"), item("2", "Hip-Hop/Rap"), item("1", "Pop"), item("3", "Radyo"), item("4", "Uzamsal Ses")]
        let sections: [[String: Any]] = [["items": items]]
        let page: [String: Any] = ["data": [["data": ["sections": sections]]]]
        let result = NativeCatalog.editorialCategories(page)
        XCTAssertEqual(result.map(\.title), ["Pop", "Hip-Hop/Rap"])
        XCTAssertEqual(result.first?.artwork, "https://is1-ssl.mzstatic.com/image/thumb/Features/test/640x426sr.jpg")
    }

    @MainActor func testRecentlyAddedSurvivesReloadAndDoesNotFollowPlayHistory() throws {
        let suite = "LibraryOrder-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = LibraryStore(context: context, insertionDefaults: defaults)
        let first = Track(id: "added-first", title: "A", artist: "Test")
        let second = Track(id: "added-second", title: "B", artist: "Test")
        store.toggleFavorite(first); store.toggleFavorite(second); store.played(first)
        XCTAssertEqual(store.recent.map(\.id), [first.id])
        XCTAssertEqual(store.recentlyAdded.map(\.id), [second.id, first.id])
        let restored = LibraryStore(context: context, insertionDefaults: defaults)
        XCTAssertEqual(restored.recentlyAdded.map(\.id), [second.id, first.id])
    }

    @MainActor func testAlbumsAndPlaylistsShareInsertionDatesAcrossReloadAndBackup() throws {
        let suite = "MixedLibrary-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        var clock = Date(timeIntervalSince1970: 100)
        let store = LibraryStore(context: context, insertionDefaults: defaults, now: { clock })
        store.createPlaylist("Older list")
        let original = Track(id: "one", title: "One", artist: "Artist", album: "Album", albumID: "a")
        clock = Date(timeIntervalSince1970: 200); store.toggleFavorite(original)
        clock = Date(timeIntervalSince1970: 300); store.createPlaylist("Newer list")
        XCTAssertEqual(store.recentlyAddedCollections.map(\.title), ["Newer list", "Album", "Older list"])
        let second = Track(id: "two", title: "Two", artist: "Artist", album: "Album", albumID: "a")
        clock = Date(timeIntervalSince1970: 400); store.toggleFavorite(second)
        clock = Date(timeIntervalSince1970: 500); store.played(original)
        XCTAssertEqual(store.recentlyAddedCollections.map(\.title), ["Album", "Newer list", "Older list"])
        XCTAssertEqual(store.recentlyAddedCollections.map { $0.addedAt.timeIntervalSince1970 }, [400, 300, 100])
        let reloaded = LibraryStore(context: context, insertionDefaults: defaults)
        XCTAssertEqual(reloaded.recentlyAddedCollections.map(\.id), store.recentlyAddedCollections.map(\.id))
        let expectedDates = store.recentlyAddedCollections.map(\.addedAt)
        let backup = try store.backup()
        // Restore into an independent empty library, preserving chronology instead of import time.
        defaults.removePersistentDomain(forName: suite)
        let other = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let restored = LibraryStore(context: ModelContext(other), insertionDefaults: defaults)
        try restored.restore(backup)
        XCTAssertEqual(restored.recentlyAddedCollections.map(\.title), ["Album", "Newer list", "Older list"])
        XCTAssertEqual(restored.recentlyAddedCollections.map(\.addedAt), expectedDates)
        XCTAssertEqual(LibraryCollectionSort.title.sorted(store.recentlyAddedCollections).map(\.title), ["Album", "Newer list", "Older list"])
    }

    @MainActor func testLegacyInsertionDatesAreSeededOnlyOnce() throws {
        let suite = "LegacyLibrary-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let one = Track(id: "legacy-one", title: "One", artist: "Test")
        let two = Track(id: "legacy-two", title: "Two", artist: "Test")
        for track in [one, two] { context.insert(SavedTrack(track)) }; try context.save()
        defaults.set([two.id, one.id], forKey: "savedTrackInsertionOrder-v1")
        let migrated = LibraryStore(context: context, insertionDefaults: defaults)
        let dates = migrated.recentlyAddedCollections.map(\.addedAt)
        migrated.played(one)
        let reloaded = LibraryStore(context: context, insertionDefaults: defaults)
        XCTAssertEqual(reloaded.recentlyAddedCollections.map(\.id), ["album:" + two.id, "album:" + one.id])
        XCTAssertEqual(reloaded.recentlyAddedCollections.map(\.addedAt), dates)
    }

    func testLibraryLayoutRestoresReorderedHiddenCategoriesAndRepairsDuplicates() {
        var layout = LibraryLayout(storedValue: "")
        layout.order = [.songs, .playlists, .songs]
        layout.hidden = [.artists, .downloads]
        let restored = LibraryLayout(storedValue: layout.storedValue)
        XCTAssertEqual(restored.order, [.songs, .playlists, .artists, .albums, .downloads])
        XCTAssertEqual(restored.visible, [.songs, .playlists, .albums])
        layout.hidden = Set(LibraryCategory.allCases)
        XCTAssertFalse(LibraryLayout(storedValue: layout.storedValue).visible.isEmpty)
        XCTAssertEqual(LibraryLayout(storedValue: "not JSON").visible, LibraryCategory.allCases)
    }

    func testRecommendationsRotateArtistsWithoutDroppingUnevenShelves() {
        let a = [Track(id: "a1", title: "A1", artist: "A"), Track(id: "a2", title: "A2", artist: "A"), Track(id: "a3", title: "A3", artist: "A")]
        let b = [Track(id: "b1", title: "B1", artist: "B")]
        let shelves = [HomeSection(id: "a", title: "A", subtitle: "", tracks: a), HomeSection(id: "empty", title: "Empty", subtitle: "", tracks: []), HomeSection(id: "b", title: "B", subtitle: "", tracks: b)]
        XCTAssertEqual(HomeFeed.interleaved(shelves).map(\.id), ["a1", "b1", "a2", "a3"])
        XCTAssertTrue(HomeFeed.interleaved([]).isEmpty)
    }

    func testLegacyArtistResponseDecodesAndDoesNotInventReleaseDate() throws {
        let json = #"{"artist":{"id":"1","name":"Test"},"tracks":[],"albums":[{"id":"2","title":"Old Album","artist":"Test","kind":"album"}]}"#
        let response = try JSONDecoder().decode(ArtistResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.featured)
        XCTAssertEqual(response.albums.first?.releaseLabel, "Öne Çıkan")
        let upcoming = MusicCollection(id: "3", title: "Future", artist: "Test", releaseDate: "2099-01-01T00:00:00Z")
        XCTAssertEqual(upcoming.releaseLabel, "Yakında")
    }

    @MainActor func testBackupRestoresEconomicalModeAndLegacyQualityConsistently() throws {
        let defaults = UserDefaults.standard
        let previousQuality = defaults.object(forKey: "quality")
        let previousMode = defaults.object(forKey: "lowDataMode")
        defer {
            if let previousQuality { defaults.set(previousQuality, forKey: "quality") } else { defaults.removeObject(forKey: "quality") }
            if let previousMode { defaults.set(previousMode, forKey: "lowDataMode") } else { defaults.removeObject(forKey: "lowDataMode") }
        }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        defaults.set("high", forKey: "quality"); defaults.set(true, forKey: "lowDataMode")
        let data = try store.backup()
        defaults.set(false, forKey: "lowDataMode")
        try store.restore(data)
        XCTAssertEqual(PlaybackPreferences.quality(), "data")
        let legacy = LibraryBackup(tracks: [], playlists: [], settings: ["quality": "high"])
        try store.restore(JSONEncoder().encode(legacy))
        XCTAssertEqual(PlaybackPreferences.quality(), "high")
    }

    func testEconomicalPreferenceOverridesPreviousHighQualityWithoutLosingChoice() throws {
        let name = "PlaybackPreferences-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("high", forKey: "quality")
        XCTAssertEqual(PlaybackPreferences.quality(defaults), "data")
        defaults.set(false, forKey: "lowDataMode")
        XCTAssertEqual(PlaybackPreferences.quality(defaults), "high")
        XCTAssertFalse(PlaybackPreferences.browseWarmupAllowed(savesData: true, unmetered: true))
        XCTAssertFalse(PlaybackPreferences.browseWarmupAllowed(savesData: false, unmetered: false))
        XCTAssertTrue(PlaybackPreferences.browseWarmupAllowed(savesData: false, unmetered: true))
        XCTAssertEqual(PlaybackPreferences.audioMegabytesPerHour(kilobits: 48), 21.6, accuracy: 0.001)
    }

    func testSequentialResolutionDoesNotStartUnusedThirdCandidate() async throws {
        let calls = PlaybackCallRecorder()
        let result: String = try await PlaybackRace.first([
            { await calls.record("bad"); throw APIError.invalidResponse },
            { await calls.record("valid"); return "audio" },
            { await calls.record("unused"); return "unnecessary" }
        ], limit: 1)
        XCTAssertEqual(result, "audio")
        let recorded = await calls.values
        XCTAssertEqual(recorded, ["bad", "valid"])
    }

    func testVerifiedRecordingSurvivesRelaunchAndRejectsChangedIdentity() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let track = Track(id: "apple:cache-test", title: "Kuzu Kuzu", artist: "Tarkan", duration: 233)
        let candidate = Track(id: "youtube:abcdefghijk", title: "Kuzu Kuzu", artist: "Tarkan", duration: 234, source: "youtube")
        let cache = RecordingMatchStore(file: file)
        await cache.save(candidate, for: track, locale: "tr-tr")
        let reopened = RecordingMatchStore(file: file)
        let remembered = await reopened.candidate(for: track, locale: "tr-tr")
        XCTAssertEqual(remembered?.id, candidate.id)
        var changed = track; changed.title = "Kuzu Kuzu Remix"
        let wrong = await reopened.candidate(for: changed, locale: "tr-tr")
        XCTAssertNil(wrong)
        let otherRegion = await reopened.candidate(for: track, locale: "en-us")
        XCTAssertNil(otherRegion)
        var incomplete = track; incomplete.duration = 0
        let enriched = await reopened.details(for: incomplete, locale: "tr-tr")
        XCTAssertEqual(enriched?.duration, 233)
        await reopened.remove(track, locale: "tr-tr")
        let removed = await reopened.candidate(for: track, locale: "tr-tr")
        XCTAssertNil(removed)
    }

    func testSmallArtworkRequestsDoNotRewriteOtherHostsOrSignedAudioURLs() throws {
        let apple = try XCTUnwrap(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/album/600x600bb.jpg"))
        XCTAssertTrue(try XCTUnwrap(ArtworkRequest.sized(apple, pixels: 150)).absoluteString.hasSuffix("160x160bb.jpg"))
        for address in ["https://rr1.googlevideo.com/videoplayback?sig=abc", "https://is1-ssl.mzstatic.com.evil.example/600x600bb.jpg"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(ArtworkRequest.sized(url, pixels: 160), url)
        }
    }

    @MainActor func testArtworkPaletteExtractsDifferentEdgeColors() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 24)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            UIColor.blue.setFill(); context.fill(CGRect(x: 24, y: 0, width: 24, height: 24))
        }
        let colors = try XCTUnwrap(ArtworkPalette.extract(image))
        XCTAssertGreaterThan(colors.left.r, colors.left.b)
        XCTAssertGreaterThan(colors.right.b, colors.right.r)
    }

    func testLivePlaybackResolutionDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_TIMING"] == "1" else {
            throw XCTSkip("Live provider timing is opt-in; offline regression tests stay deterministic.")
        }
        do {
            let response = try await API.shared.search("Tarkan Kuzu Kuzu")
            let track = try XCTUnwrap(response.tracks.first(where: { NativeCatalog.canonical($0.title) == "kuzu kuzu" }))
            let start = Date()
            let asset = try await API.shared.resolve(track)
            let cold = Date().timeIntervalSince(start) * 1000
            XCTAssertTrue(NativeCatalog.durationCompatible(expected: track.duration, actual: asset.duration))
            let warmStart = Date()
            let cached = try await API.shared.resolve(track)
            let warm = Date().timeIntervalSince(warmStart) * 1000
            XCTAssertEqual(asset.path, cached.path)
            print("KLYMUSIC_LIVE_TIMING cold_resolve_ms=\(Int(cold)) cached_resolve_ms=\(Int(warm))")
        } catch {
            print("KLYMUSIC_LIVE_TIMING unavailable=\(error.localizedDescription)")
            throw XCTSkip("Live provider unavailable from CI: \(error.localizedDescription)")
        }
    }

    func testPlaybackRaceSkipsFailureAndCancelsSlowAlternative() async throws {
        let canceled = expectation(description: "Losing network request is canceled")
        let value: String = try await PlaybackRace.first([
            { throw APIError.invalidResponse },
            {
                do { try await Task.sleep(for: .seconds(30)); return "slow" }
                catch { canceled.fulfill(); throw error }
            },
            { try await Task.sleep(for: .milliseconds(30)); return "validated" }
        ])
        XCTAssertEqual(value, "validated")
        await fulfillment(of: [canceled], timeout: 1)
    }

    func testPlaybackRacePropagatesFailureWhenNoRecordingIsValid() async {
        do {
            let _: String = try await PlaybackRace.first([
                { throw APIError.invalidResponse },
                { throw APIError.server("no valid audio") }
            ])
            XCTFail("Invalid candidates cannot become a playable recording")
        } catch let error as PlaybackFailure { XCTAssertEqual(error, .invalidMedia) }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancelingPlaybackRaceCancelsAllCandidates() async throws {
        let started = expectation(description: "Candidate started")
        let canceled = expectation(description: "Candidate canceled")
        let request = Task {
            let _: String = try await PlaybackRace.first([{
                started.fulfill()
                do { try await Task.sleep(for: .seconds(30)); return "stale" }
                catch { canceled.fulfill(); throw error }
            }])
        }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        do { try await request.value; XCTFail("Canceled selection must not return stale audio") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [canceled], timeout: 1)
    }

    func testNativeMatchingRejectsWrongRecording() {
        let original = Track(id: "apple:123", title: "Kuzu Kuzu", artist: "Tarkan", duration: 233)
        let matching = Track(id: "youtube:abcdefghijk", title: "Kuzu Kuzu Orijinal Versiyon", artist: "Tarkan", duration: 234)
        XCTAssertGreaterThan(NativeCatalog.match(original, matching), 0.9)
        XCTAssertEqual(NativeCatalog.match(original, Track(id: matching.id, title: "Kuzu Kuzu Remix", artist: "Tarkan", duration: 234)), 0)
        XCTAssertEqual(NativeCatalog.match(original, Track(id: matching.id, title: "Kuzu Kuzu", artist: "Someone else", duration: 234)), 0)
        XCTAssertEqual(NativeCatalog.match(original, Track(id: matching.id, title: "Kuzu Kuzu", artist: "Tarkan", duration: 80)), 0)
    }
    func testDirectPlaybackAcceptsOnlyProviderMediaURLs() throws {
        for address in ["https://aac.saavncdn.com/song.mp4", "https://rr1.googlevideo.com/videoplayback?expire=123"] {
            XCTAssertTrue(NativeCatalog.allowedMediaURL(try XCTUnwrap(URL(string: address))))
        }
        for address in ["http://aac.saavncdn.com/song.mp4", "https://googlevideo.com.evil.example/song.mp4", "https://googlevideo.com@evil.example/song", "https://127.0.0.1/song", "https://aac.saavncdn.com:444/song"] {
            XCTAssertFalse(NativeCatalog.allowedMediaURL(try XCTUnwrap(URL(string: address))))
        }
    }
    func testLyricsTimestampsAndRepeatedLines() {
        let parsed = LyricLine.parse("[ar:Artist]\n[00:01.2][00:09.025]Hello\n[00:04.12]World\n[00:07]   ")
        XCTAssertEqual(parsed.map(\.text), ["Hello", "World", "Hello"])
        XCTAssertEqual(parsed[0].time, 1.2, accuracy: 0.001)
        XCTAssertEqual(parsed[1].time, 4.12, accuracy: 0.001)
        XCTAssertEqual(parsed[2].time, 9.025, accuracy: 0.001)
    }
    func testTimeFormattingHandlesUnloadedDuration() {
        XCTAssertEqual(Track.time(.nan), "0:00")
        XCTAssertEqual(Track.time(-4), "0:00")
        XCTAssertEqual(Track.time(125.7), "2:05")
    }
    @MainActor func testSeekClampsClockAndIgnoresNonFiniteInput() {
        let player = MusicPlayer()
        player.duration = 60
        player.seek(90)
        XCTAssertEqual(player.position, 60)
        player.seek(-12)
        XCTAssertEqual(player.position, 0)
        player.seek(.nan)
        XCTAssertEqual(player.position, 0)
    }
    @MainActor func testSwitchingLyricsKeepsNewRequestLoadingUntilItCompletes() async throws {
        let first = Track(id: "lyrics-test-" + UUID().uuidString, title: "First", artist: "Test")
        let second = Track(id: "lyrics-test-" + UUID().uuidString, title: "Second", artist: "Test")
        var requests: [String: CheckedContinuation<LyricsResponse, Error>] = [:]
        let firstStarted = expectation(description: "First request started")
        let secondStarted = expectation(description: "Second request started")
        let player = MusicPlayer { track in
            try await withCheckedThrowingContinuation { continuation in
                requests[track.id] = continuation
                (track.id == first.id ? firstStarted : secondStarted).fulfill()
            }
        }
        defer {
            try? FileManager.default.removeItem(at: MusicFiles.lyrics(first.id))
            try? FileManager.default.removeItem(at: MusicFiles.lyrics(second.id))
        }
        player.current = first
        player.loadLyrics(force: true)
        await fulfillment(of: [firstStarted], timeout: 2)
        player.current = second
        player.loadLyrics()
        await fulfillment(of: [secondStarted], timeout: 2)
        // Simulate a source that completes its old request even after cancellation.
        requests[first.id]?.resume(returning: LyricsResponse(plain: "Old test line", instrumental: false))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(player.lyricsLoading)
        XCTAssertNil(player.lyrics)
        requests[second.id]?.resume(returning: LyricsResponse(plain: "New test line", instrumental: false))
        for _ in 0..<50 {
            if !player.lyricsLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(player.lyrics?.plain, "New test line")
        XCTAssertFalse(player.lyricsLoading)
        XCTAssertNil(player.lyricsError)
    }
    @MainActor func testLyricsNetworkFailureCanBeRetried() async throws {
        var attempts = 0
        let track = Track(id: "lyrics-retry-" + UUID().uuidString, title: "Retry", artist: "Test")
        let player = MusicPlayer { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return LyricsResponse(plain: "Recovered test line", instrumental: false)
        }
        defer { try? FileManager.default.removeItem(at: MusicFiles.lyrics(track.id)) }
        player.current = track
        player.loadLyrics(force: true)
        for _ in 0..<50 {
            if !player.lyricsLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(player.lyricsError)
        XCTAssertNil(player.lyrics)
        player.loadLyrics(force: true)
        for _ in 0..<50 {
            if !player.lyricsLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(player.lyricsError)
        XCTAssertEqual(player.lyrics?.plain, "Recovered test line")
        XCTAssertEqual(attempts, 2)
    }
    @MainActor func testBackupMergesWithoutInventingDownloads() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: config)
        let source = LibraryStore(context: ModelContext(container))
        let track = Track(id: "apple:1", title: "Test", artist: "Artist")
        source.toggleFavorite(track); source.played(track); source.createPlaylist("Mix")
        source.add(track, to: try XCTUnwrap(source.playlists.first))
        let backup = try source.backup()
        try source.restore(backup)
        XCTAssertEqual(source.favorites.count, 1)
        XCTAssertEqual(source.playlists.count, 1)
        XCTAssertEqual(source.playlists[0].trackIDs, [track.id])
        XCTAssertEqual(source.saved[0].playCount, 1)
        XCTAssertNil(source.localURL(track.id))
    }
    @MainActor func testOneHundredRapidSelectionsKeepLastTrack() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        var wave = Data()
        func text(_ value: String) { wave.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wave.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(36 + 88200)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(44100)); number(UInt32(88200)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(88200)); wave.append(Data(repeating: 0, count: 88200))
        var tracks: [Track] = []
        var files: [URL] = []
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }
        for index in 0..<3 {
            let track = Track(id: "apple:\(9000 + index)", title: "Generated \(index)", artist: "KlyMusic Test", duration: 1)
            let name = UUID().uuidString + ".wav"
            let url = MusicFiles.downloads.appendingPathComponent(name)
            try wave.write(to: url); files.append(url)
            store.markDownloaded(track, filename: name); tracks.append(track)
        }
        let player = MusicPlayer(); player.library = store
        for index in 0..<100 { player.play(tracks[index % 3], in: tracks) }
        for _ in 0..<40 {
            if player.engine.items().count == 2 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(player.current?.id, tracks[0].id)
        XCTAssertEqual(player.engine.items().count, 2)
        XCTAssertNil(player.error)
        player.playNext(tracks[2])
        XCTAssertEqual(player.queue.map(\.id), [tracks[0].id, tracks[2].id, tracks[1].id])
        player.playNext(tracks[2])
        XCTAssertEqual(player.queue.count, 3)
        player.setSleepAtEnd()
        XCTAssertTrue(player.sleepAtEnd)
        player.setSleep(minutes: 15)
        XCTAssertFalse(player.sleepAtEnd)
        XCTAssertNotNil(player.sleepUntil)
        player.setSleep(minutes: nil)
        XCTAssertNil(player.sleepUntil)
        player.engine.pause()
    }
    @MainActor func testReplayingSameLocalTrackKeepsLoadedLyrics() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "replay-lyrics-" + UUID().uuidString, title: "Replay", artist: "Test", duration: 4)
        // Exercise the AAC format written by downloads, using the same real encoder
        // fixture as the queue-transition and download-validation regressions.
        let source = try downloadFixture(seconds: 4)
        defer { try? FileManager.default.removeItem(at: source) }
        let filename = UUID().uuidString + ".m4a"
        let file = MusicFiles.downloads.appendingPathComponent(filename)
        try FileManager.default.moveItem(at: source, to: file)
        store.markDownloaded(track, filename: filename)
        var lyricRequests = 0
        let player = MusicPlayer { _ in
            lyricRequests += 1
            return LyricsResponse(plain: "Keep this lyric", synced: "[00:00.00]Keep this lyric", instrumental: false)
        }
        player.library = store
        defer {
            player.engine.pause()
            player.engine.removeAllItems()
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: MusicFiles.lyrics(track.id))
        }
        player.play(track, in: [track])
        for _ in 0..<100 {
            if player.pendingTrack == nil, player.engine.currentItem != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let firstItem = try XCTUnwrap(player.engine.currentItem)
        player.engine.pause()
        // Readiness is asynchronous; pause the short fixture before waiting so it
        // cannot finish while a slow simulator is still delivering status changes.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            firstItem.status != .unknown
        }, object: nil)
        await fulfillment(of: [ready], timeout: 10)
        XCTAssertEqual(firstItem.status, .readyToPlay)
        player.loadLyrics(force: true)
        for _ in 0..<100 {
            if !player.lyricsLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(player.lyrics?.plain, "Keep this lyric")
        player.seek(2)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertGreaterThan(player.position, 1)
        player.play(track, in: [track])
        for _ in 0..<100 {
            if player.pendingTrack == nil, player.engine.currentItem !== firstItem { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let replayItem = try XCTUnwrap(player.engine.currentItem)
        XCTAssertFalse(replayItem === firstItem)
        XCTAssertNil(player.error)
        XCTAssertEqual(player.current?.id, track.id)
        XCTAssertEqual(player.lyrics?.plain, "Keep this lyric")
        XCTAssertEqual(player.lyrics?.lines.first?.text, "Keep this lyric")
        XCTAssertEqual(lyricRequests, 1)
    }
    @MainActor func testCancelDuringDownloadResolutionDoesNotRecreateJob() async throws {
        let track = Track(id: "cancel-download-" + UUID().uuidString, title: "Cancel", artist: "Test")
        let started = expectation(description: "Download resolution started")
        var pending: CheckedContinuation<PlaybackAsset, Error>?
        let manager = DownloadManager { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation; started.fulfill()
            }
        }
        manager.enqueue(track)
        await fulfillment(of: [started], timeout: 2)
        manager.cancel(track.id)
        pending?.resume(throwing: URLError(.notConnectedToInternet))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(manager.jobs[track.id])
    }
    @MainActor func testPausedResolvingDownloadCanBeImmediatelyResumed() async throws {
        let track = Track(id: "resume-download-" + UUID().uuidString, title: "Resume", artist: "Test")
        let firstStarted = expectation(description: "First resolution started")
        let secondStarted = expectation(description: "Resumed resolution started")
        var pending: [CheckedContinuation<PlaybackAsset, Error>] = []
        let manager = DownloadManager { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                pending.append(continuation)
                (pending.count == 1 ? firstStarted : secondStarted).fulfill()
            }
        }
        manager.enqueue(track)
        await fulfillment(of: [firstStarted], timeout: 2)
        manager.pause(track.id)
        XCTAssertEqual(manager.jobs[track.id]?.paused, true)
        manager.enqueue(track)
        pending[0].resume(throwing: URLError(.cancelled))
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(manager.jobs[track.id]?.paused, false)
        XCTAssertEqual(manager.jobs[track.id]?.failed, false)
        manager.cancel(track.id)
        pending[1].resume(throwing: URLError(.cancelled))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(manager.jobs[track.id])
    }
    @MainActor func testRecoveredDownloadIsSavedWithoutReconnect() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "recovered-download-" + UUID().uuidString, title: "Recovered", artist: "Test")
        _ = store.record(track); store.commit()
        let manager = DownloadManager(); manager.library = store
        let task = CompletedDownloadTask(id: track.id, identifier: 801)
        let source = try downloadFixture()
        let expected = try Data(contentsOf: source)
        defer { cleanupDownload(track) }
        let completed = expectation(description: "Recovered download stored")
        manager.backgroundCompletion = { completed.fulfill() }
        manager.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: source)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [completed], timeout: 3)
        let saved = try XCTUnwrap(store.localURL(track.id))
        XCTAssertEqual(try Data(contentsOf: saved), expected)
        XCTAssertNil(manager.jobs[track.id])
    }

    @MainActor func testBackgroundCompletionWaitsForValidationAndStorage() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "pending-download-" + UUID().uuidString, title: "Pending", artist: "Test")
        _ = store.record(track); store.commit()
        var validation: CheckedContinuation<Bool, Error>?
        let started = expectation(description: "Audio validation suspended")
        let manager = DownloadManager(validator: { _ in
            try await withCheckedThrowingContinuation { validation = $0; started.fulfill() }
        })
        manager.library = store
        defer { cleanupDownload(track) }
        var completionCalled = false
        let completed = expectation(description: "Stored before background completion")
        manager.backgroundCompletion = {
            completionCalled = true
            XCTAssertNotNil(store.localURL(track.id))
            XCTAssertNil(manager.jobs[track.id])
            completed.fulfill()
        }
        manager.urlSession(.shared, downloadTask: CompletedDownloadTask(id: track.id, identifier: 802), didFinishDownloadingTo: try downloadFixture())
        // Finish-events can arrive before the MainActor validation task even starts.
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(completionCalled)
        XCTAssertNil(store.localURL(track.id))
        validation?.resume(returning: true)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(completionCalled)
    }

    @MainActor func testBackgroundCompletionDrainsAllValidationsIncludingFailure() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let tracks = (0..<2).map { Track(id: "parallel-download-\($0)-" + UUID().uuidString, title: "Parallel", artist: "Test") }
        tracks.forEach { _ = store.record($0) }; store.commit()
        var validations: [String: CheckedContinuation<Bool, Error>] = [:]
        let started = expectation(description: "Both validations suspended"); started.expectedFulfillmentCount = 2
        let manager = DownloadManager(validator: { url in
            try await withCheckedThrowingContinuation { continuation in
                validations[String(url.lastPathComponent.split(separator: ".")[0])] = continuation
                started.fulfill()
            }
        })
        manager.library = store
        defer { tracks.forEach(cleanupDownload) }
        var completionCalled = false
        let completed = expectation(description: "Both finalizations drained")
        manager.backgroundCompletion = { completionCalled = true; completed.fulfill() }
        for (index, track) in tracks.enumerated() {
            manager.urlSession(.shared, downloadTask: CompletedDownloadTask(id: track.id, identifier: 810 + index), didFinishDownloadingTo: try downloadFixture())
        }
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [started], timeout: 2)
        validations[MusicFiles.filename(tracks[0].id)]?.resume(returning: false)
        for _ in 0..<100 {
            if manager.jobs[tracks[0].id]?.failed == true { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(manager.jobs[tracks[0].id]?.failed, true)
        XCTAssertFalse(completionCalled)
        validations[MusicFiles.filename(tracks[1].id)]?.resume(returning: true)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertNil(store.localURL(tracks[0].id))
        XCTAssertNotNil(store.localURL(tracks[1].id))
    }

    @MainActor func testCancelledFinalizationCannotRestoreDownload() async throws {
        try await assertInterruptedFinalizationStaysUndownloaded(paused: false)
    }

    @MainActor func testPausedFinalizationCannotRestoreDownload() async throws {
        try await assertInterruptedFinalizationStaysUndownloaded(paused: true)
    }

    @MainActor private func assertInterruptedFinalizationStaysUndownloaded(paused: Bool) async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "interrupted-download-" + UUID().uuidString, title: "Interrupted", artist: "Test")
        _ = store.record(track); store.commit()
        var validation: CheckedContinuation<Bool, Error>?
        var staged: URL?
        let started = expectation(description: "Validation suspended before interruption")
        let manager = DownloadManager(validator: { url in
            staged = url
            return try await withCheckedThrowingContinuation { validation = $0; started.fulfill() }
        })
        manager.library = store
        defer { cleanupDownload(track) }
        let task = CompletedDownloadTask(id: track.id, identifier: 820)
        let completed = expectation(description: "Interrupted finalization drained")
        manager.backgroundCompletion = { completed.fulfill() }
        manager.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: try downloadFixture())
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [started], timeout: 2)
        if paused { manager.pause(track.id) } else { manager.cancel(track.id) }
        validation?.resume(returning: true)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertNil(store.localURL(track.id))
        XCTAssertNil(store.saved.first(where: { $0.id == track.id })?.downloadFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(staged).path))
        if paused { XCTAssertEqual(manager.jobs[track.id]?.paused, true) }
        else { XCTAssertNil(manager.jobs[track.id]) }
        // A duplicate late callback from the old task must not be adopted after interruption.
        let late = expectation(description: "Late callback rejected")
        manager.backgroundCompletion = { late.fulfill() }
        manager.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: try downloadFixture())
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [late], timeout: 2)
        XCTAssertNil(store.localURL(track.id))
    }

    @MainActor func testOldRecoveredCallbackCannotReplaceResolvingDownload() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "replacement-download-" + UUID().uuidString, title: "Replacement", artist: "Test")
        _ = store.record(track); store.commit()
        var resolution: CheckedContinuation<PlaybackAsset, Error>?
        let started = expectation(description: "Replacement resolution suspended")
        let manager = DownloadManager(validator: { _ in XCTFail("Old callback must not replace a resolving download"); return true }, resolver: { _, _ in
            try await withCheckedThrowingContinuation { resolution = $0; started.fulfill() }
        })
        manager.library = store
        defer { cleanupDownload(track) }
        manager.enqueue(track)
        await fulfillment(of: [started], timeout: 2)
        let completed = expectation(description: "Old callback discarded")
        manager.backgroundCompletion = { completed.fulfill() }
        manager.urlSession(.shared, downloadTask: CompletedDownloadTask(id: track.id, identifier: 825), didFinishDownloadingTo: try downloadFixture())
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertNil(store.localURL(track.id))
        XCTAssertNotNil(manager.jobs[track.id])
        XCTAssertEqual(manager.jobs[track.id]?.failed, false)
        manager.cancel(track.id)
        resolution?.resume(throwing: URLError(.cancelled))
    }

    @MainActor func testBackgroundCompletionIncludesHTTPAndTransportFailures() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let tracks = (0..<2).map { Track(id: "failed-download-\($0)-" + UUID().uuidString, title: "Failure", artist: "Test") }
        tracks.forEach { _ = store.record($0) }; store.commit()
        let manager = DownloadManager(validator: { _ in XCTFail("Invalid HTTP response must not validate audio"); return true })
        manager.library = store
        let source = try downloadFixture()
        defer { try? FileManager.default.removeItem(at: source); tracks.forEach(cleanupDownload) }
        let completed = expectation(description: "Failures stored before completion")
        manager.backgroundCompletion = {
            for track in tracks { XCTAssertEqual(manager.jobs[track.id]?.failed, true); XCTAssertNil(store.localURL(track.id)) }
            completed.fulfill()
        }
        manager.urlSession(.shared, downloadTask: CompletedDownloadTask(id: tracks[0].id, identifier: 830, status: 500), didFinishDownloadingTo: source)
        manager.urlSession(.shared, task: CompletedDownloadTask(id: tracks[1].id, identifier: 831), didCompleteWithError: URLError(.notConnectedToInternet))
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [completed], timeout: 2)
    }

    private func downloadFixture(seconds: Int = 1) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        do {
            let audio = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000
            ])
            let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 44100))
            samples.frameLength = samples.frameCapacity
            let channel = try XCTUnwrap(samples.floatChannelData?[0])
            for frame in 0..<Int(samples.frameLength) { channel[frame] = Float(0.1 * sin(2 * .pi * 440 * Double(frame) / 44100)) }
            for _ in 0..<seconds { try audio.write(from: samples) }
        }
        return url
    }

    private func cleanupDownload(_ track: Track) {
        try? FileManager.default.removeItem(at: MusicFiles.downloads.appendingPathComponent(MusicFiles.filename(track.id) + ".m4a"))
        try? FileManager.default.removeItem(at: MusicFiles.lyrics(track.id))
    }

    @MainActor func testLibraryDurationEnrichmentPreservesAppleMetadataAndFlags() throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let original = Track(id: "duration-enrichment-" + UUID().uuidString, title: "KAYIP KALP", artist: "BLOK3", album: "Apple Album", artwork: "https://example.com/apple-cover.jpg")
        store.toggleFavorite(original)
        let saved = try XCTUnwrap(store.saved.first)
        let played = Date(timeIntervalSince1970: 123456)
        saved.lastPlayed = played; saved.playCount = 7; saved.downloadFile = "existing-file.m4a"
        store.commit()
        var supplied = original
        supplied.duration = 153
        supplied.title = "Different provider title"; supplied.artist = "Different provider artist"
        supplied.album = "Different provider album"; supplied.artwork = "https://example.com/other-cover.jpg"
        _ = store.record(supplied); store.commit()
        let item = try XCTUnwrap(store.saved.first)
        let enriched = try XCTUnwrap(item.track)
        XCTAssertEqual(enriched.duration, 153)
        XCTAssertEqual(enriched.title, original.title)
        XCTAssertEqual(enriched.artist, original.artist)
        XCTAssertEqual(enriched.album, original.album)
        XCTAssertEqual(enriched.artwork, original.artwork)
        XCTAssertTrue(item.favorite)
        XCTAssertEqual(item.lastPlayed, played)
        XCTAssertEqual(item.playCount, 7)
        XCTAssertEqual(item.downloadFile, "existing-file.m4a")
        XCTAssertEqual(store.saved.count, 1)
    }

    @MainActor func testLibraryPositiveDurationRemainsAuthoritative() throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let original = Track(id: "duration-authority-" + UUID().uuidString, title: "KAYIP KALP", artist: "BLOK3", duration: 153)
        _ = store.record(original); store.commit()
        var replacement = original
        replacement.duration = 300
        _ = store.record(replacement)
        replacement.duration = 0
        _ = store.record(replacement); store.commit()
        XCTAssertEqual(try XCTUnwrap(store.saved.first?.track).duration, 153)
    }

    @MainActor func testDownloadRejectsFileWithDifferentSongDuration() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "wrong-duration-download-" + UUID().uuidString, title: "KAYIP KALP", artist: "BLOK3", duration: 153)
        _ = store.record(track); store.commit()
        let manager = DownloadManager()
        manager.library = store
        let source = try downloadFixture() // A valid AAC file containing only one second of audio.
        defer { try? FileManager.default.removeItem(at: source); cleanupDownload(track) }
        let completed = expectation(description: "Wrong-duration file rejected before background completion")
        manager.backgroundCompletion = {
            XCTAssertEqual(manager.jobs[track.id]?.failed, true)
            XCTAssertEqual(manager.jobs[track.id]?.status, L("İndirilen dosya bu şarkının süresiyle eşleşmiyor. Yeniden indir."))
            XCTAssertNil(store.localURL(track.id))
            XCTAssertNil(store.saved.first(where: { $0.id == track.id })?.downloadFile)
            completed.fulfill()
        }
        manager.urlSession(.shared, downloadTask: CompletedDownloadTask(id: track.id, identifier: 840), didFinishDownloadingTo: source)
        manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(store.saved.first(where: { $0.id == track.id })?.track?.duration, 153)
    }

    func testAudioFileDecoderMeasuresCompleteAACFrames() throws {
        let source = try downloadFixture(seconds: 10)
        defer { try? FileManager.default.removeItem(at: source) }
        let decoded = try DownloadAudioContainer.decodedFileDuration(at: source)
        XCTAssertEqual(decoded, 10, accuracy: 0.15)
    }

    func testOrdinaryAACContainerPassesWithoutRewriting() async throws {
        let stage = try downloadFixture()
        defer { try? FileManager.default.removeItem(at: stage) }
        let originalBytes = try Data(contentsOf: stage)
        let verified = try await DownloadAudioContainer.verifiedDuration(at: stage, expected: 1)
        XCTAssertEqual(verified, 1, accuracy: 0.15)
        XCTAssertEqual(try Data(contentsOf: stage), originalBytes)
    }

    func testGenuinelyLongAudioContainerIsRejectedWithoutTrimming() async throws {
        let stage = try downloadFixture(seconds: 10)
        defer { try? FileManager.default.removeItem(at: stage) }
        let originalBytes = try Data(contentsOf: stage)
        do {
            _ = try await DownloadAudioContainer.verifiedDuration(at: stage, expected: 5)
            XCTFail("A genuinely longer recording must be rejected.")
        } catch {
            guard case APIError.server(let message) = error else {
                XCTFail("Expected duration mismatch, got \(error)")
                return
            }
            XCTAssertEqual(message, L("İndirilen dosya bu şarkının süresiyle eşleşmiyor. Yeniden indir."))
            XCTAssertEqual(try Data(contentsOf: stage), originalBytes)
            let duration = try await AVURLAsset(url: stage).load(.duration).seconds
            XCTAssertEqual(duration, 10, accuracy: 0.15)
        }
    }

    func testListeningLocaleUsesPhoneLanguageAndRegionalEnglishStore() {
        let turkishAbroad = ListeningLocale.resolve(preferredLanguages: ["tr-TR", "en-US"], regionCode: "US")
        XCTAssertEqual(turkishAbroad.languageCode, "tr")
        XCTAssertEqual(turkishAbroad.countryCode, "tr")
        let britishEnglish = ListeningLocale.resolve(preferredLanguages: ["en-GB"], regionCode: "US")
        XCTAssertEqual(britishEnglish.languageCode, "en")
        XCTAssertEqual(britishEnglish.countryCode, "gb")
        XCTAssertNotEqual(turkishAbroad.cacheKey, britishEnglish.cacheKey)
    }

    func testAppLanguageFollowsSystemUnlessManuallySelected() {
        XCTAssertEqual(AppLanguage.resolve(selection: "system", preferredLanguages: ["tr-TR"]), "tr")
        XCTAssertEqual(AppLanguage.resolve(selection: nil, preferredLanguages: ["en-GB"]), "en")
        XCTAssertEqual(AppLanguage.resolve(selection: "en", preferredLanguages: ["tr-TR"]), "en")
        XCTAssertEqual(AppLanguage.resolve(selection: "tr", preferredLanguages: ["en-GB"]), "tr")
        XCTAssertEqual(AppLanguage.resolve(selection: "invalid", preferredLanguages: ["tr-TR"]), "tr")
    }

    @MainActor func testUpcomingQueueExcludesHistoryAndProtectsCurrent() {
        let tracks = (0..<5).map { Track(id: "queue-\($0)", title: "Song \($0)", artist: "Test") }
        let player = MusicPlayer()
        player.queue = tracks; player.current = tracks[1]; player.index = 1
        XCTAssertEqual(player.upcomingTracks.map(\.id), tracks.dropFirst(2).map(\.id))
        player.removeUpcoming(id: tracks[0].id)
        player.removeUpcoming(id: tracks[1].id)
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id))
        player.removeUpcoming(id: tracks[3].id)
        XCTAssertEqual(player.queue.map(\.id), [tracks[0], tracks[1], tracks[2], tracks[4]].map(\.id))
        XCTAssertEqual(player.index, 1)
        XCTAssertEqual(player.current?.id, tracks[1].id)
    }

    @MainActor func testQueueReorderUsesStableIdentityWhenPlaybackAdvances() {
        let tracks = (0..<6).map { Track(id: "queue-\($0)", title: "Song \($0)", artist: "Test") }
        let player = MusicPlayer()
        player.queue = tracks; player.current = tracks[1]; player.index = 1
        let snapshot = player.upcomingTracks
        player.moveUpcoming(from: IndexSet(integer: 3), to: 0, snapshot: snapshot)
        XCTAssertEqual(player.queue.map(\.id), [0, 1, 5, 2, 3, 4].map { tracks[$0].id })
        XCTAssertEqual(player.index, 1)
        // A drag started on song 2, but song 2 became current before the drop.
        player.queue = tracks; player.current = tracks[2]; player.index = 2
        player.moveUpcoming(from: IndexSet(integer: 0), to: 4, snapshot: snapshot)
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id))
        player.moveUpcoming(from: IndexSet(integer: 3), to: 0, snapshot: snapshot)
        XCTAssertEqual(player.queue.map(\.id), [0, 1, 2, 5, 3, 4].map { tracks[$0].id })
        XCTAssertEqual(player.index, 2)
    }

    @MainActor func testClearingUpcomingLeavesHistoryCurrentAndPlayerItemUntouched() {
        let tracks = (0..<4).map { Track(id: "queue-\($0)", title: "Song \($0)", artist: "Test") }
        let player = MusicPlayer()
        player.queue = tracks; player.current = tracks[1]; player.index = 1; player.repeatMode = .all
        let playingItem = AVPlayerItem(url: URL(fileURLWithPath: "/unloaded-current.m4a"))
        player.engine.insert(playingItem, after: nil)
        player.clearUpcoming()
        XCTAssertEqual(player.queue.map(\.id), tracks.prefix(2).map(\.id))
        XCTAssertTrue(player.upcomingTracks.isEmpty)
        XCTAssertEqual(player.current?.id, tracks[1].id)
        XCTAssertTrue(player.engine.currentItem === playingItem)
        XCTAssertEqual(player.repeatMode, .off)
    }

    @MainActor func testQueueItemTransitionKeepsMetadataClockAndIndexTogether() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let tracks = [Track(id: "queue-a-" + UUID().uuidString, title: "First song", artist: "Test", duration: 1),
                      Track(id: "queue-b-" + UUID().uuidString, title: "Second song", artist: "Test", duration: 1)]
        let fixture = try downloadFixture()
        defer { try? FileManager.default.removeItem(at: fixture); tracks.forEach(cleanupDownload) }
        for track in tracks {
            let filename = MusicFiles.filename(track.id) + ".m4a"
            try FileManager.default.copyItem(at: fixture, to: MusicFiles.downloads.appendingPathComponent(filename))
            store.markDownloaded(track, filename: filename)
        }
        let player = MusicPlayer(); player.library = store
        defer { player.engine.pause() }
        player.play(tracks[0], in: tracks)
        for _ in 0..<150 {
            if player.current?.id == tracks[0].id { player.engine.pause() }
            if player.engine.items().count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(player.engine.items().count, 2)
        let prepared = try XCTUnwrap(player.engine.items().last)
        let started = Date()
        player.playUpcoming(id: tracks[1].id)
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id))
        let controlMS = Date().timeIntervalSince(started) * 1000
        XCTAssertTrue(player.engine.currentItem === prepared, "Next must reuse the already prepared player item")
        print("PREPARED_ITEM_SWITCH_CONTROL_MS=\(controlMS) (control path, not audible latency)")
        for _ in 0..<100 {
            if player.current?.id == tracks[1].id { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(player.current?.id, tracks[1].id)
        XCTAssertEqual(player.index, 1)
        XCTAssertEqual(player.duration, 1, accuracy: 0.15)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, tracks[1].title)
        player.seek(0.45)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(player.position, 0.45, accuracy: 0.15)
        XCTAssertEqual(store.saved.first(where: { $0.id == tracks[1].id })?.playCount, 1)
    }

    @MainActor func testCachedCombinedRecordingIsRejectedBeforePlayback() async throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let track = Track(id: "wrong-local-" + UUID().uuidString, title: "Kayıp Kalp", artist: "BLOK3", duration: 153)
        let fixture = try downloadFixture()
        let filename = MusicFiles.filename(track.id) + ".m4a"
        try FileManager.default.moveItem(at: fixture, to: MusicFiles.downloads.appendingPathComponent(filename))
        store.markDownloaded(track, filename: filename)
        defer { cleanupDownload(track) }
        let player = MusicPlayer(); player.library = store
        player.play(track, in: [track])
        for _ in 0..<100 {
            if player.pendingTrack == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(player.error)
        XCTAssertNil(player.engine.currentItem)
        XCTAssertNil(player.current)
    }

    @MainActor func testDisplayedDurationHonorsVerifiedPlaybackBoundary() {
        let item = AVPlayerItem(url: URL(fileURLWithPath: "/not-loaded.m4a"))
        item.forwardPlaybackEndTime = CMTime(seconds: 153.25, preferredTimescale: 600)
        XCTAssertEqual(MusicPlayer.playbackDuration(item), 153.25, accuracy: 0.01)
    }

    func testReleasedMashupAndMedleyRecordingsArePlayableIdentities() {
        let mashup = Track(id: "apple:mashup", title: "Azeri Mashup 2", artist: "Dj Roshka", duration: 220)
        let copy = Track(id: "youtube:abcdefghijk", title: "Dj Roshka - Azeri Mashup 2 (Official Audio)", artist: "Dj Roshka - Topic", duration: 221)
        XCTAssertGreaterThan(NativeCatalog.match(mashup, copy), 0.9)
        XCTAssertEqual(NativeCatalog.normalized("Əzizim"), NativeCatalog.normalized("Ezizim"))
        var other = copy; other.title = "Azeri Mashup 3"
        XCTAssertEqual(NativeCatalog.match(mashup, other), 0)
        other = copy; other.duration = 440
        XCTAssertEqual(NativeCatalog.match(mashup, other), 0)
        let medley = Track(id: "apple:medley", title: "Live Medley", artist: "Artist", duration: 500)
        XCTAssertGreaterThan(NativeCatalog.match(medley, medley), 0.9)
    }

    func testReportedMashupMatchesExplicitCollaborationWithCreditedUploader() {
        let original = Track(id: "apple:1617467916", title: "Azeri Mashup 2", artist: "Dj Roshka", duration: 224.365)
        let video = Track(id: "youtube:abcdefghijk", title: "Sevil Sevinc & Dj Roshka - Azeri Mashup 2", artist: "Sevil Sevinc", duration: 225)
        XCTAssertGreaterThan(NativeCatalog.match(original, video), 0.9)
        var unrelated = video; unrelated.artist = "Unrelated Covers"
        XCTAssertEqual(NativeCatalog.match(original, unrelated), 0)
        unrelated = video; unrelated.title = "Sevil Sevinc & Other Producer - Azeri Mashup 2"
        XCTAssertEqual(NativeCatalog.match(original, unrelated), 0)
        unrelated = video; unrelated.duration = 450
        XCTAssertEqual(NativeCatalog.match(original, unrelated), 0)
    }

    func testFeaturedArtistsCanMoveBetweenTitleAndArtistMetadata() {
        let requested = Track(id: "apple:featured", title: "Gece (feat. Konuk)", artist: "Sanatçı", duration: 220)
        let copy = Track(id: "youtube:abcdefghijk", title: "Gece (Official Audio)", artist: "Sanatçı, Konuk", duration: 221)
        XCTAssertGreaterThan(NativeCatalog.match(requested, copy), 0.9)
        var wrong = copy; wrong.artist = "Sanatçı, Başkası"
        XCTAssertEqual(NativeCatalog.match(requested, wrong), 0)
        wrong = copy; wrong.title = "Gece Remix"
        XCTAssertEqual(NativeCatalog.match(requested, wrong), 0)
    }

    func testMissingAppleDurationCanMatchIdentityWithoutAcceptingWrongVersions() {
        let requested = Track(id: "apple:missing", title: "Say It Right", artist: "Nelly Furtado")
        let copy = Track(id: "youtube:abcdefghijk", title: "Say It Right (Official Music Video)", artist: "Nelly Furtado - Topic", duration: 240)
        XCTAssertTrue(NativeCatalog.sameRecordingIdentity(requested, copy))
        XCTAssertEqual(NativeCatalog.match(requested, copy), 0, "Duration still has to be established before accepting media")
        var remix = copy; remix.title = "Say It Right Remix"
        XCTAssertFalse(NativeCatalog.sameRecordingIdentity(requested, remix))
    }

    func testAudioFormatDurationCoversURLsWithoutDurationAndRejectsConflicts() throws {
        let bare = try XCTUnwrap(URL(string: "https://rr1.googlevideo.com/videoplayback?id=audio"))
        XCTAssertEqual(NativeCatalog.streamDuration(bare, formatDuration: 223.08), 223.08)
        XCTAssertNil(NativeCatalog.streamDuration(bare, formatDuration: nil))
        XCTAssertNil(NativeCatalog.streamDuration(bare, formatDuration: .nan))
        let signed = try XCTUnwrap(URL(string: "https://rr1.googlevideo.com/videoplayback?dur=223.08"))
        XCTAssertNil(NativeCatalog.streamDuration(signed, formatDuration: 440))
        let duplicate = try XCTUnwrap(URL(string: "https://rr1.googlevideo.com/videoplayback?dur=223&dur=440"))
        XCTAssertNil(NativeCatalog.streamDuration(duplicate, formatDuration: 223))
    }

    func testReportedAzeriMashupResolutionDiagnostic() async throws {
        try await reportedPlaybackDiagnostic(Track(id: "apple:1617467916", title: "Azeri Mashup 2", artist: "Dj Roshka", duration: 224.365))
    }
    func testReportedSayItRightResolutionDiagnostic() async throws {
        try await reportedPlaybackDiagnostic(Track(id: "apple:1445855879", title: "Say It Right", artist: "Nelly Furtado", duration: 223.08))
    }
    private func reportedPlaybackDiagnostic(_ track: Track) async throws {
        guard ProcessInfo.processInfo.environment["KLYMUSIC_LIVE_TIMING"] == "1" else { throw XCTSkip("Live provider diagnostic is opt-in") }
        do {
            let prepareStart = Date()
            await API.shared.prepareMatches([track])
            let preparationMS = Date().timeIntervalSince(prepareStart) * 1000
            let start = Date()
            let asset = try await API.shared.resolve(track, quality: "data")
            let resolveMS = Date().timeIntervalSince(start) * 1000
            XCTAssertTrue(NativeCatalog.durationCompatible(expected: track.duration, actual: asset.duration))
            let repeatStart = Date()
            let repeated = try await API.shared.resolve(track, quality: "data")
            let cacheMS = Date().timeIntervalSince(repeatStart) * 1000
            XCTAssertEqual(asset.path, repeated.path)
            print("REPORTED_PLAYBACK id=\(track.id) provider=\(asset.provider) prepare_ms=\(preparationMS) prepared_resolve_ms=\(resolveMS) cache_ms=\(cacheMS) audible_measurement=false")
        } catch {
            print("REPORTED_PLAYBACK id=\(track.id) unavailable=\(error.localizedDescription)")
            throw XCTSkip("Live provider unavailable from CI for \(track.title): \(error.localizedDescription)")
        }
    }

    func testSourceMatchingRejectsCombinedAndDifferentRecordings() {
        let target = Track(id: "apple:6773420730", title: "Kayıp Kalp", artist: "BLOK3", duration: 153.231)
        let correct = Track(id: "youtube:nKHGXOdJlNc", title: "Kayıp Kalp", artist: "BLOK3", duration: 154)
        XCTAssertGreaterThan(NativeCatalog.match(target, correct), 0.9)
        for candidate in [
            Track(id: correct.id, title: "Kayıp Kalp / TRALALA", artist: "BLOK3", duration: 153),
            Track(id: correct.id, title: "Kayıp Kalp", artist: "BLOK3", duration: 309),
            Track(id: correct.id, title: "Kayıp Kalp Medley", artist: "BLOK3", duration: 153),
            Track(id: correct.id, title: "Kayıp Kalp", artist: "Someone else", duration: 153),
            Track(id: correct.id, title: "Kayıp Kalp (Sped Up)", artist: "BLOK3", duration: 153),
            Track(id: correct.id, title: "Kayıp Kalp", artist: "BLOK3", duration: 0)
        ] { XCTAssertEqual(NativeCatalog.match(target, candidate), 0) }
        var unknown = target; unknown.duration = 0
        XCTAssertEqual(NativeCatalog.match(unknown, correct), 0)
        XCTAssertGreaterThan(NativeCatalog.match(target, Track(id: correct.id, title: "BLOK3 - Kayıp Kalp (Official Audio)", artist: "BLOK3 - Topic", duration: 154)), 0.9)
    }
    
    func testDurationCompatibilityRejectsUnknownAndMergedAudio() throws {
        XCTAssertTrue(NativeCatalog.durationCompatible(expected: 153.231, actual: 153.22))
        XCTAssertTrue(NativeCatalog.durationCompatible(expected: 153.231, actual: 154))
        for value in [0.0, -1.0, Double.nan, Double.infinity, 309.0] {
            XCTAssertFalse(NativeCatalog.durationCompatible(expected: 153.231, actual: value))
        }
        XCTAssertFalse(NativeCatalog.durationCompatible(expected: 0, actual: 153))
        XCTAssertEqual(NativeCatalog.mediaDuration(try XCTUnwrap(URL(string: "https://rr1.googlevideo.com/videoplayback?dur=153.231"))), 153.231)
        for address in ["https://rr1.googlevideo.com/videoplayback", "https://rr1.googlevideo.com/videoplayback?dur=nan", "https://rr1.googlevideo.com/videoplayback?dur=153&dur=309", "https://googlevideo.com.evil.example/videoplayback?dur=153"] {
            XCTAssertNil(NativeCatalog.mediaDuration(try XCTUnwrap(URL(string: address))))
        }
    }

    @MainActor func testUnknownBackupVersionIsRejected() throws {
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        let data = Data(#"{"version":99,"tracks":[],"playlists":[],"settings":{}}"#.utf8)
        XCTAssertThrowsError(try store.restore(data))
    }
    func testPlaybackResolutionIsSharedAndCached() async throws {
        let cache = PlaybackAssetCache()
        let gate = PlaybackResolutionGate()
        let started = expectation(description: "Single resolver started")
        let loader: @Sendable () async throws -> PlaybackAsset = {
            started.fulfill()
            return await gate.wait("shared")
        }
        let first = Task { try await cache.value(for: "song", loader: loader) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await cache.value(for: "song", loader: loader) }
        try await Task.sleep(for: .milliseconds(30))
        await gate.complete("shared", asset: Self.cacheAsset("shared"))
        let values = try await [first.value, second.value]
        XCTAssertEqual(values.map(\.id), ["shared", "shared"])
        let cached = try await cache.value(for: "song") { XCTFail("A fresh asset must be reused"); return Self.cacheAsset("unexpected") }
        XCTAssertEqual(cached.id, "shared")
    }

    func testCancelingWarmupDoesNotCancelPlaybackWaitingForSameSong() async throws {
        let cache = PlaybackAssetCache()
        let gate = PlaybackResolutionGate()
        let started = expectation(description: "Resolver started")
        let loader: @Sendable () async throws -> PlaybackAsset = {
            started.fulfill()
            return await gate.wait("shared")
        }
        let warmup = Task { try await cache.value(for: "song", loader: loader) }
        await fulfillment(of: [started], timeout: 2)
        let playback = Task { try await cache.value(for: "song", loader: loader) }
        try await Task.sleep(for: .milliseconds(30))
        warmup.cancel()
        do { _ = try await warmup.value; XCTFail("Canceled warmup must stop waiting") }
        catch is CancellationError { }
        await gate.complete("shared", asset: Self.cacheAsset("playing"))
        let asset = try await playback.value
        XCTAssertEqual(asset.id, "playing")
    }

    func testCanceledResolutionCannotOverwriteNewRequestForSameSong() async throws {
        let cache = PlaybackAssetCache()
        let gate = PlaybackResolutionGate()
        let oldStarted = expectation(description: "Old resolver started")
        let old = Task {
            try await cache.value(for: "song") {
                oldStarted.fulfill()
                return await gate.wait("old") // Simulates a transport that finishes after cancellation.
            }
        }
        await fulfillment(of: [oldStarted], timeout: 2)
        old.cancel()
        do { _ = try await old.value; XCTFail("Canceled request must stop waiting immediately") }
        catch is CancellationError { }
        let newStarted = expectation(description: "New resolver started")
        let new = Task {
            try await cache.value(for: "song") {
                newStarted.fulfill()
                return await gate.wait("new")
            }
        }
        await fulfillment(of: [newStarted], timeout: 2)
        await gate.complete("old", asset: Self.cacheAsset("stale"))
        await gate.complete("new", asset: Self.cacheAsset("new"))
        let asset = try await new.value
        XCTAssertEqual(asset.id, "new")
        let cached = try await cache.value(for: "song") { XCTFail("New request should be cached"); return Self.cacheAsset("unexpected") }
        XCTAssertEqual(cached.id, "new")
    }

    func testPlaybackCacheRenewsExpiringAssetsAndEvictsLeastRecentlyUsed() async throws {
        let cache = PlaybackAssetCache(capacity: 2)
        _ = try await cache.value(for: "expiring") { Self.cacheAsset("expired", lifetime: 30) }
        let renewed = try await cache.value(for: "expiring") { Self.cacheAsset("renewed") }
        XCTAssertEqual(renewed.id, "renewed")
        _ = try await cache.value(for: "second") { Self.cacheAsset("second") }
        _ = try await cache.value(for: "expiring") { XCTFail("Recently used asset should be cached"); return Self.cacheAsset("unexpected") }
        _ = try await cache.value(for: "third") { Self.cacheAsset("third") }
        let reloaded = try await cache.value(for: "second") { Self.cacheAsset("second-reloaded") }
        XCTAssertEqual(reloaded.id, "second-reloaded")
        await cache.invalidate()
        let invalidated = try await cache.value(for: "second") { Self.cacheAsset("after-failure") }
        XCTAssertEqual(invalidated.id, "after-failure")
    }

    private static func cacheAsset(_ id: String, lifetime: Double = 1800) -> PlaybackAsset {
        PlaybackAsset(id: id, path: "https://rr1.googlevideo.com/audio", provider: "youtube", codec: "aac", bitrate: 128,
                      expiresAt: Date().timeIntervalSince1970 + lifetime, duration: 180)
    }

}

private actor PlaybackCallRecorder {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}

private final class CompletedDownloadTask: URLSessionDownloadTask, @unchecked Sendable {
    private let identifier: Int
    private let httpResponse: HTTPURLResponse
    override var taskIdentifier: Int { identifier }
    override var state: URLSessionTask.State { .completed }
    override var response: URLResponse? { httpResponse }
    init(id: String, identifier: Int, status: Int = 200) {
        self.identifier = identifier
        httpResponse = HTTPURLResponse(url: URL(string: "https://aac.saavncdn.com/test.mp4")!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "audio/mp4"])!
        super.init()
        taskDescription = id
    }
    override func cancel() {}
    override func cancel(byProducingResumeData completionHandler: @escaping @Sendable (Data?) -> Void) { completionHandler(nil) }
}

private actor PlaybackResolutionGate {
    private var continuations: [String: CheckedContinuation<PlaybackAsset, Never>] = [:]
    private var completed: [String: PlaybackAsset] = [:]
    func wait(_ key: String) async -> PlaybackAsset {
        if let asset = completed.removeValue(forKey: key) { return asset }
        return await withCheckedContinuation { continuations[key] = $0 }
    }
    func complete(_ key: String, asset: PlaybackAsset) {
        if let continuation = continuations.removeValue(forKey: key) { continuation.resume(returning: asset) }
        else { completed[key] = asset }
    }
}

extension CoreTests {
    @MainActor func testLibraryRestoreMergesExistingListsAndRepeatedImportsWithoutLosingLocalSongs() throws {
        let suite = "LibraryMerge-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container), insertionDefaults: defaults)
        let local = Track(id: "local", title: "Local", artist: "Test")
        let imported = Track(id: "imported", title: "Imported", artist: "Test")
        store.createPlaylist("Local name")
        let playlist = try XCTUnwrap(store.playlists.first)
        store.add(local, to: playlist)
        let created = Date(timeIntervalSince1970: 100)
        let duplicateID = UUID()
        let backup = LibraryBackup(
            tracks: [.init(track: imported, favorite: true, lastPlayed: nil, playCount: 0, addedAt: Date(timeIntervalSince1970: 200))],
            playlists: [
                .init(id: playlist.id, name: "Older name", trackIDs: [imported.id, "missing", imported.id], createdAt: created),
                .init(id: duplicateID, name: "Imported list", trackIDs: [imported.id, imported.id], createdAt: created),
                .init(id: duplicateID, name: "Duplicate", trackIDs: [local.id, imported.id], createdAt: created)
            ], settings: [:])
        let data = try JSONEncoder().encode(backup)
        try store.restore(data); try store.restore(data)
        XCTAssertEqual(store.playlists.count, 2)
        XCTAssertEqual(playlist.name, "Local name", "A restore must retain local renames")
        XCTAssertEqual(playlist.trackIDs, [local.id, imported.id], "Missing backed-up songs must be merged without removing local ones")
        XCTAssertEqual(playlist.createdAt, created)
        XCTAssertEqual(store.playlists.first { $0.id == duplicateID }?.trackIDs, [imported.id, local.id])
        XCTAssertEqual(store.saved.count, 2)
    }

    @MainActor func testLibraryRestoredTrackOrderUsesDatesWithStableTies() throws {
        let suite = "LibraryRestoredDates-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = LibraryStore(context: context, insertionDefaults: defaults)
        let older = Track(id: "older", title: "Older", artist: "Test")
        let newestB = Track(id: "new-b", title: "New B", artist: "Test")
        let newestA = Track(id: "new-a", title: "New A", artist: "Test")
        let entries = [(newestB, 300.0), (newestA, 300.0), (older, 100.0)].map { track, time in
            LibraryBackup.BackupTrack(track: track, favorite: true, lastPlayed: nil, playCount: 0, addedAt: Date(timeIntervalSince1970: time))
        }
        try store.restore(JSONEncoder().encode(LibraryBackup(tracks: entries, playlists: [], settings: [:])))
        XCTAssertEqual(store.recentlyAdded.map(\.id), [newestA.id, newestB.id, older.id])
        store.played(older)
        let reopened = LibraryStore(context: context, insertionDefaults: defaults)
        XCTAssertEqual(reopened.recentlyAdded.map(\.id), [newestA.id, newestB.id, older.id])
        XCTAssertEqual(reopened.recentlyAddedCollections.map(\.id), ["album:new-a", "album:new-b", "album:older"])
    }

    @MainActor func testLibraryBackupKeepsCategoryLayoutAndSortWithoutResettingLegacyPreferences() throws {
        let keys = ["libraryLayout-v1", "librarySort-v1"]
        let defaults = UserDefaults.standard
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(context: ModelContext(container))
        var layout = LibraryLayout(storedValue: "")
        layout.order = [.songs, .albums, .downloads, .artists, .playlists]; layout.hidden = [.artists]
        defaults.set(layout.storedValue, forKey: keys[0]); defaults.set("artist", forKey: keys[1])
        let backup = try store.backup()
        defaults.removeObject(forKey: keys[0]); defaults.set("added", forKey: keys[1])
        try store.restore(backup)
        XCTAssertEqual(LibraryLayout(storedValue: defaults.string(forKey: keys[0]) ?? ""), layout)
        XCTAssertEqual(defaults.string(forKey: keys[1]), "artist")
        for settings in [[String: String](), ["libraryLayout-v1": "bad JSON", "librarySort-v1": "not-a-sort"]] {
            try store.restore(JSONEncoder().encode(LibraryBackup(tracks: [], playlists: [], settings: settings)))
            XCTAssertEqual(LibraryLayout(storedValue: defaults.string(forKey: keys[0]) ?? ""), layout)
            XCTAssertEqual(defaults.string(forKey: keys[1]), "artist")
        }
    }
}

extension CoreTests {
    func testAudioHeaderProbeStopsIgnoredRangeResponseAfterContainerHeader() async throws {
        let path = "/valid-" + UUID().uuidString
        let request = URLRequest(url: URL(string: "https://rr1.googlevideo.com" + path)!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioProbeTestProtocol.self]
        let valid = try await AudioHeaderProbe.check(request, configuration: configuration)
        XCTAssertTrue(valid)
        for _ in 0..<100 {
            if AudioProbeTestProtocol.didStop(path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(AudioProbeTestProtocol.didStop(path), "An HTTP 200 response ignoring Range must be cancelled after its header")
    }

    func testAudioHeaderProbeRejectsWrongContainerAndHTTPFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioProbeTestProtocol.self]
        for path in ["/invalid-", "/status-"] {
            let request = URLRequest(url: URL(string: "https://rr1.googlevideo.com" + path + UUID().uuidString)!)
            let valid = try await AudioHeaderProbe.check(request, configuration: configuration)
            XCTAssertFalse(valid)
        }
    }

    func testAudioHeaderProbeCancellationReleasesPendingTransfer() async throws {
        let path = "/pending-" + UUID().uuidString
        let request = URLRequest(url: URL(string: "https://rr1.googlevideo.com" + path)!)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AudioProbeTestProtocol.self]
        let operation = Task { try await AudioHeaderProbe.check(request, configuration: configuration) }
        for _ in 0..<100 {
            if AudioProbeTestProtocol.didStart(path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(AudioProbeTestProtocol.didStart(path))
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled header probes must not complete successfully") }
        catch is CancellationError { }
        for _ in 0..<100 {
            if AudioProbeTestProtocol.didStop(path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(AudioProbeTestProtocol.didStop(path))
    }
}

private final class AudioProbeTestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var stopped = Set<String>()
    private static var started = Set<String>()
    static func didStart(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return started.contains(path)
    }
    static func didStop(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return stopped.contains(path)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.lock(); Self.started.insert(url.path); Self.lock.unlock()
        let status = url.path.hasPrefix("/status-") ? 403 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "50000000", "Content-Type": "audio/mp4"])!, cacheStoragePolicy: .notAllowed)
        if url.path.hasPrefix("/pending-") || status != 200 { return }
        let header = url.path.hasPrefix("/valid-") ? Data([0, 0, 0, 24] + Array("ftypM4A ".utf8)) : Data(repeating: 0, count: 12)
        client?.urlProtocol(self, didLoad: header)
        // A server ignoring Range would keep streaming. The probe must stop before that.
    }
    override func stopLoading() {
        Self.lock.lock(); Self.stopped.insert(request.url!.path); Self.lock.unlock()
    }
}


extension CoreTests {
    func testLyricsCacheRejectsWhitespaceAndMalformedTimedContent() throws {
        let invalid = [
            LyricsResponse(plain: " \n\t ", synced: nil, instrumental: false),
            LyricsResponse(plain: nil, synced: "not timed lyrics", instrumental: false),
            LyricsResponse(plain: nil, synced: "[ar:Artist]\n[00:01.20]   ", instrumental: false)
        ]
        for response in invalid {
            XCTAssertFalse(response.hasContent)
            XCTAssertNil(LyricsCacheEntry.decode(try JSONEncoder().encode(response)))
            let envelope = LyricsCacheEntry(response: response, fetchedAt: .now)
            XCTAssertNil(LyricsCacheEntry.decode(try JSONEncoder().encode(envelope)))
        }
        XCTAssertTrue(LyricsResponse(plain: nil, synced: "[00:01.20]Words", instrumental: false).hasContent)
        XCTAssertTrue(LyricsResponse(plain: nil, synced: nil, instrumental: true).hasContent)
    }

    func testLyricsCacheRefreshesLegacyAndExpiresByContentQuality() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let plain = LyricsResponse(plain: "Saved words", instrumental: false)
        let timed = LyricsResponse(plain: "Saved words", synced: "[00:01.00]Saved words", instrumental: false)
        let instrumental = LyricsResponse(instrumental: true)
        let legacy = try XCTUnwrap(LyricsCacheEntry.decode(try JSONEncoder().encode(plain)))
        XCTAssertTrue(legacy.needsRefresh(at: now))
        XCTAssertEqual(legacy.response.plain, "Saved words")
        let cases: [(LyricsResponse, TimeInterval)] = [(plain, 86400), (timed, 604800), (instrumental, 21600)]
        for (response, lifetime) in cases {
            let entry = LyricsCacheEntry(response: response, fetchedAt: now)
            XCTAssertFalse(entry.needsRefresh(at: now.addingTimeInterval(lifetime - 1)))
            XCTAssertTrue(entry.needsRefresh(at: now.addingTimeInterval(lifetime)))
            XCTAssertTrue(entry.needsRefresh(at: now.addingTimeInterval(-1)))
            let obsolete = LyricsCacheEntry(response: response, fetchedAt: now, resolverVersion: 0)
            XCTAssertTrue(obsolete.needsRefresh(at: now))
        }
    }

    @MainActor func testEmptyLyricsAreNotPersistedAndCanRetryWithoutForce() async throws {
        let track = Track(id: "empty-lyrics-" + UUID().uuidString, title: "Retry", artist: "Test")
        let file = MusicFiles.lyrics(track.id)
        defer { try? FileManager.default.removeItem(at: file) }
        var attempts = 0
        let player = MusicPlayer { _ in
            attempts += 1
            if attempts == 1 { return LyricsResponse(plain: " \n ", synced: "malformed", instrumental: false) }
            return LyricsResponse(plain: "Recovered", synced: "[00:01.00]Recovered", instrumental: false)
        }
        player.current = track
        player.loadLyrics()
        let first = observeLyricsCompletion(player)
        await fulfillment(of: [first.0], timeout: 2)
        withExtendedLifetime(first.1) {}
        XCTAssertNil(player.lyrics)
        XCTAssertNil(player.lyricsError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        player.loadLyrics()
        let second = observeLyricsCompletion(player)
        await fulfillment(of: [second.0], timeout: 2)
        withExtendedLifetime(second.1) {}
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(player.lyrics?.lines.first?.text, "Recovered")
        let cached = try XCTUnwrap(LyricsCacheEntry.decode(Data(contentsOf: file)))
        XCTAssertEqual(cached.resolverVersion, LyricsCacheEntry.currentResolverVersion)
        XCTAssertFalse(cached.needsRefresh())
    }

    @MainActor func testLegacyPlainLyricsStayVisibleWhileUpgradingToTimedLyrics() async throws {
        let track = Track(id: "legacy-lyrics-" + UUID().uuidString, title: "Legacy", artist: "Test")
        let file = MusicFiles.lyrics(track.id)
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(LyricsResponse(plain: "Offline words", instrumental: false)).write(to: file)
        var pending: CheckedContinuation<LyricsResponse, Error>?
        var attempts = 0
        let started = expectation(description: "Stale lyrics refreshed")
        let player = MusicPlayer { _ in
            attempts += 1
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation; started.fulfill()
            }
        }
        player.current = track
        player.loadLyrics()
        let completion = observeLyricsCompletion(player)
        XCTAssertEqual(player.lyrics?.plain, "Offline words")
        XCTAssertFalse(player.lyricsLoading)
        await fulfillment(of: [started], timeout: 2)
        player.loadLyrics() // Reopening the sheet must not duplicate its background request.
        XCTAssertEqual(attempts, 1)
        pending?.resume(returning: LyricsResponse(plain: "Offline words", synced: "[00:01.00]Offline words", instrumental: false))
        await fulfillment(of: [completion.0], timeout: 2)
        withExtendedLifetime(completion.1) {}
        XCTAssertEqual(player.lyrics?.lines.first?.text, "Offline words")
        XCTAssertNil(player.lyricsError)
        let saved = try XCTUnwrap(LyricsCacheEntry.decode(Data(contentsOf: file)))
        XCTAssertFalse(saved.needsRefresh())
        XCTAssertEqual(saved.response.lines.count, 1)
    }

    @MainActor func testStaleLyricsSurviveOfflineAndEmptyRefreshWithoutAnErrorOverlay() async throws {
        for offline in [true, false] {
            let track = Track(id: "offline-lyrics-" + UUID().uuidString, title: "Offline", artist: "Test")
            let file = MusicFiles.lyrics(track.id)
            defer { try? FileManager.default.removeItem(at: file) }
            let cached = LyricsCacheEntry(response: LyricsResponse(plain: "Keep offline words", instrumental: false), fetchedAt: .now.addingTimeInterval(-2 * 24 * 60 * 60))
            let savedData = try JSONEncoder().encode(cached)
            try savedData.write(to: file)
            let player = MusicPlayer { _ in
                if offline { throw URLError(.notConnectedToInternet) }
                return LyricsResponse(instrumental: false)
            }
            player.current = track
            player.loadLyrics(force: offline)
            let completion = observeLyricsCompletion(player)
            XCTAssertEqual(player.lyrics?.plain, "Keep offline words")
            XCTAssertFalse(player.lyricsLoading)
            await fulfillment(of: [completion.0], timeout: 2)
            withExtendedLifetime(completion.1) {}
            XCTAssertEqual(player.lyrics?.plain, "Keep offline words")
            XCTAssertFalse(player.lyricsLoading)
            XCTAssertNil(player.lyricsError)
            XCTAssertEqual(try Data(contentsOf: file), savedData)
        }
    }

    @MainActor func testFreshTimedLyricsUseCacheWithoutAProviderRequest() throws {
        let track = Track(id: "fresh-lyrics-" + UUID().uuidString, title: "Fresh", artist: "Test")
        let file = MusicFiles.lyrics(track.id)
        defer { try? FileManager.default.removeItem(at: file) }
        let response = LyricsResponse(plain: "Cached words", synced: "[00:01.00]Cached words", instrumental: false)
        try JSONEncoder().encode(LyricsCacheEntry(response: response, fetchedAt: .now)).write(to: file)
        let player = MusicPlayer { _ in
            XCTFail("Fresh timed lyrics must not request the provider again")
            return LyricsResponse(instrumental: false)
        }
        player.current = track
        player.loadLyrics()
        XCTAssertEqual(player.lyrics?.lines.first?.text, "Cached words")
        XCTAssertFalse(player.lyricsLoading)
        XCTAssertNil(player.lyricsError)
    }

    @MainActor func testTimedLyricsAreNotDowngradedByPlainOrInstrumentalRefresh() async throws {
        for replacement in [LyricsResponse(plain: "Plain replacement", instrumental: false), LyricsResponse(instrumental: true)] {
            let track = Track(id: "timed-lyrics-" + UUID().uuidString, title: "Timed", artist: "Test")
            let file = MusicFiles.lyrics(track.id)
            defer { try? FileManager.default.removeItem(at: file) }
            let response = LyricsResponse(plain: "Timed words", synced: "[00:01.00]Timed words", instrumental: false)
            let cached = LyricsCacheEntry(response: response, fetchedAt: .now.addingTimeInterval(-8 * 24 * 60 * 60))
            try JSONEncoder().encode(cached).write(to: file)
            let player = MusicPlayer { _ in replacement }
            player.current = track
            player.loadLyrics()
            let completion = observeLyricsCompletion(player)
            await fulfillment(of: [completion.0], timeout: 2)
            withExtendedLifetime(completion.1) {}
            XCTAssertEqual(player.lyrics?.lines.first?.text, "Timed words")
            let refreshed = try XCTUnwrap(LyricsCacheEntry.decode(Data(contentsOf: file)))
            XCTAssertFalse(refreshed.needsRefresh())
            XCTAssertEqual(refreshed.response.lines.first?.text, "Timed words")
        }
    }

    @MainActor private func observeLyricsCompletion(_ player: KlyMusic.MusicPlayer) -> (XCTestExpectation, AnyCancellable) {
        // Call immediately after loadLyrics(), before yielding to its async provider request.
        let completed = expectation(description: "Lyrics request finished")
        let observation = player.$lyricsLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in completed.fulfill() }
        return (completed, observation)
    }
}


extension CoreTests {
    func testGeneralRecordingIdentityGeneratedMultilingualMetadataCorpus() {
        // 12 languages x 5 recording versions x 8 presentation styles. These are
        // generated metadata controls, not live-catalogue playback measurements.
        let examples: [(String, String, String)] = [
            ("Gece Yolu", "Sanatçı Bir", "Konuk İki"),
            ("Étoile du Soir", "Artiste Un", "Invité Deux"),
            ("Ночной свет", "Артист Один", "Гость Два"),
            ("Το φως", "Καλλιτέχνης", "Φωνή"),
            ("青い空", "音楽家", "客演"),
            ("빛나는 밤", "가수 하나", "가수 둘"),
            ("نور الليل", "فنان", "ضيف"),
            ("शाम का गीत", "कलाकार", "अतिथि"),
            ("Luz do Mar", "Artista", "Convidado"),
            ("Gecənin Nəğməsi", "Sənətçi", "Qonaq"),
            ("Hjärtats Sång", "Sångare", "Gäst"),
            ("Күн нұры", "Әнші", "Қонақ")
        ]
        let versions = ["", " (Remix)", " (Live)", " (Acoustic)", " (Instrumental)"]
        let presentations = [" (Official Audio)", " [Official Music Video]", " (Lyrics)", " (4K)",
                             " (Official Lyric Video) (HD)", " Official Audio", " Official Video HD", "【Official Audio】"]
        var accepted = 0, rejected = 0
        for (title, artist, guest) in examples {
            for version in versions {
                let requested = Track(id: "apple:corpus", title: title + " (feat. " + guest + ")" + version, artist: artist, duration: 180)
                for presentation in presentations {
                    let candidate = Track(id: "youtube:abcdefghijk", title: title + version + presentation, artist: artist + ", " + guest, duration: 181)
                    XCTAssertTrue(RecordingIdentity.same(requested, candidate), candidate.title + " / " + artist)
                    accepted += 1
                    var wrong = candidate; wrong.artist = artist + ", Uncredited Guest"
                    XCTAssertFalse(RecordingIdentity.same(requested, wrong), "Missing/replaced collaborators must not match")
                    rejected += 1
                }
                for otherVersion in versions where otherVersion != version {
                    let wrong = Track(id: "youtube:abcdefghijk", title: title + otherVersion, artist: artist + " & " + guest, duration: 180)
                    XCTAssertFalse(RecordingIdentity.same(requested, wrong), requested.title + " vs " + wrong.title)
                    rejected += 1
                }
            }
        }
        XCTAssertEqual(accepted, 480)
        XCTAssertEqual(rejected, 720)
        print("RECORDING_IDENTITY_CORPUS accepted=480 rejected=720 languages=12 (generated metadata controls, not live playback)")
    }

    func testGeneralFeaturedRemixCreditsCanMoveBeforeOrAfterVersionBrackets() {
        let requested = Track(id: "apple:remix", title: "PUSH2START (feat. Chris Brown & Sean Paul) (Remix)", artist: "Tyla", duration: 180)
        let candidate = Track(id: "youtube:abcdefghijk", title: "PUSH2START (Remix) [Official Audio]", artist: "Tyla, Chris Brown, Sean Paul", duration: 181)
        XCTAssertTrue(RecordingIdentity.same(requested, candidate))
        var unbracketed = requested; unbracketed.title = "PUSH2START feat. Chris Brown & Sean Paul (Remix)"
        XCTAssertTrue(RecordingIdentity.same(unbracketed, candidate))
        var missing = candidate; missing.artist = "Tyla, Sean Paul"
        XCTAssertFalse(RecordingIdentity.same(requested, missing))
        var original = candidate; original.title = "PUSH2START (Official Audio)"
        XCTAssertFalse(RecordingIdentity.same(requested, original))
        XCTAssertTrue(RecordingIdentity.lookupTitles(requested).contains("PUSH2START (Remix)"))
        XCTAssertTrue(RecordingIdentity.queries(requested).contains { $0.contains("Chris Brown") && $0.contains("Sean Paul") && $0.contains("remix") })
    }

    func testGeneralCreditSeparatorsRequireIndependentEvidenceForBandNames() {
        let requested = Track(id: "apple:collaboration", title: "Midnight", artist: "Alpha & Beta", duration: 180)
        for artists in ["Alpha, Beta", "Alpha feat. Beta", "Alpha x Beta", "Alpha and Beta", "Beta & Alpha"] {
            XCTAssertTrue(RecordingIdentity.same(requested, Track(id: "youtube:abcdefghijk", title: "Midnight (Official Video)", artist: artists)), artists)
        }
        let band = Track(id: "apple:band", title: "Moon", artist: "Of Mountains and Seas")
        XCTAssertTrue(RecordingIdentity.same(band, Track(id: "youtube:abcdefghijk", title: "Moon", artist: "Of Mountains and Seas - Topic")))
        XCTAssertFalse(RecordingIdentity.same(band, Track(id: "youtube:abcdefghijk", title: "Of Mountains and Seas - Moon", artist: "Seas")), "A band-name word is not proof of a credited uploader")
        XCTAssertFalse(RecordingIdentity.same(Track(id: "apple:x", title: "Moon", artist: "Alpha and Beta"), Track(id: "youtube:abcdefghijk", title: "Moon", artist: "Alpha x Beta")), "Two ambiguous parses must not corroborate each other")
        let video = Track(id: "youtube:abcdefghijk", title: "Alpha & Beta - Midnight (Official Video)", artist: "Alpha")
        XCTAssertTrue(RecordingIdentity.same(requested, video))
        var unrelated = video; unrelated.artist = "Unrelated Uploader"
        XCTAssertFalse(RecordingIdentity.same(requested, unrelated))
    }

    func testGeneralUnicodeRomanizationDoesNotUsePerArtistAliasesOrTitleSubstrings() {
        let original = Track(id: "apple:unicode", title: "Sigma Boy (Сигма Бой)", artist: "Betsy & Maria Iankovskaia")
        for artists in ["Betsy, Maria Yankovskaya", "Бэтси, Мария Янковская"] {
            let candidate = Track(id: "youtube:abcdefghijk", title: "Сигма Бой (Official Audio)", artist: artists)
            XCTAssertTrue(RecordingIdentity.same(original, candidate))
        }
        let transliterated = Track(id: "apple:transliterated", title: "Ночной свет", artist: "Ирина")
        XCTAssertTrue(RecordingIdentity.same(transliterated, Track(id: "youtube:abcdefghijk", title: "Nochnoy svet", artist: "Irina")))
        let directLatin = Track(id: "apple:latin", title: "Moon", artist: "Daria")
        XCTAssertFalse(RecordingIdentity.same(directLatin, Track(id: "youtube:abcdefghijk", title: "Moon", artist: "Darya")), "Same-script names must not use unrestricted spelling fuzziness")
        let unrelatedAlias = Track(id: "apple:alias", title: "Night (День)", artist: "Artist")
        XCTAssertFalse(RecordingIdentity.same(unrelatedAlias, Track(id: "youtube:abcdefghijk", title: "Night", artist: "Artist")))
        let exact = Track(id: "apple:exact", title: "Midnight", artist: "Alpha")
        for title in ["Midnight Sun", "Midnight Medley", "Midnight (Radio Edit)", "Midnight (Sped Up)", "Midnight (Slowed)"] {
            XCTAssertFalse(RecordingIdentity.same(exact, Track(id: "youtube:abcdefghijk", title: title, artist: "Alpha")), title)
        }
    }
}

private final class CatalogResponseProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var storage: ((URLRequest) -> [String: Any])?
    static var handler: ((URLRequest) -> [String: Any])? {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static func query(_ request: URLRequest) -> String? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["query"] as? String
    }
    override func startLoading() {
        let object = Self.handler?(request) ?? ["contents": []]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}


extension CoreTests {
    func testGeneralRecordingIdentitySoundtrackAndOriginalVersionPresentationKeepsRealVersions() {
        let soundtrack = Track(id: "apple:soundtrack", title: "Gece (From \"Film Soundtrack\")", artist: "Artist")
        for title in ["Gece", "Gece (Original Version)", "Gece Original Version", "Gece [Orijinal Versiyon]", "Gece Orijinal Versiyon (Official Audio)"] {
            XCTAssertTrue(RecordingIdentity.same(soundtrack, Track(id: "youtube:abcdefghijk", title: title, artist: "Artist")), title)
        }
        var remix = soundtrack; remix.title = "Gece (From \"Film Soundtrack\") (Remix)"
        XCTAssertTrue(RecordingIdentity.same(remix, Track(id: "youtube:abcdefghijk", title: "Gece (Remix) (Original Version)", artist: "Artist")))
        for title in ["Gece (Remix)", "Gece (Live)", "Gece (Acoustic)", "Gece (Original Remix)"] {
            XCTAssertFalse(RecordingIdentity.same(soundtrack, Track(id: "youtube:abcdefghijk", title: title, artist: "Artist")), title)
        }
        XCTAssertFalse(RecordingIdentity.same(remix, Track(id: "youtube:abcdefghijk", title: "Gece (Original Version)", artist: "Artist")))
        XCTAssertTrue(RecordingIdentity.lookupTitles(soundtrack).contains("Gece"))
    }
}
