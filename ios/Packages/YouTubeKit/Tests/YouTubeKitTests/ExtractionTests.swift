//
//  ExtractionTests.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 04.09.21.
//

import XCTest
@testable import YouTubeKit

@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
final class ExtractionTests: XCTestCase {
    
    func testOriginalAudioMarkerAllowsPresentationPunctuation() throws {
        for name in ["English (Original)", "English(Original)", "(original)", "English [Original]", "English — Original"] {
            let stream = try Self.audioTrackFormat(name, isDefault: true)
            XCTAssertEqual(Extraction.filterOutDubbedAudio(streamManifest: [stream]).count, 1, name)
        }
    }

    func testLocalizedOriginalAudioMarkersKeepTheOriginalTrack() throws {
        for name in ["Türkçe (Orijinal)", "Русский (Оригинал)", "日本語（オリジナル）", "한국어 (원본)", "中文（原声）"] {
            let stream = try Self.audioTrackFormat(name, isDefault: false)
            XCTAssertEqual(Extraction.filterOutDubbedAudio(streamManifest: [stream]).count, 1, name)
        }
    }

    func testDefaultDubbedAndUnknownAudioTracksAreNotAssumedOriginal() throws {
        for name in ["English", "English (Dubbed)", "English (not original)", "English (non-original)", "English (Dubbed Original)", "English (Unoriginal)"] {
            let stream = try Self.audioTrackFormat(name, isDefault: true)
            XCTAssertTrue(Extraction.filterOutDubbedAudio(streamManifest: [stream]).isEmpty, name)
        }
    }

    func testOriginalAudioFilteringKeepsAllItsRenditionsAndUnlabelledAudio() throws {
        let original = try Self.audioTrackFormat("English (Original)", isDefault: false)
        let dubbed = try Self.audioTrackFormat("Türkçe (Dubbed)", isDefault: true)
        let unlabelled = try JSONDecoder().decode(InnerTube.StreamingData.Format.self, from: Data(#"{"itag":139,"url":"https://rr1.googlevideo.com/audio","mimeType":"audio/mp4; codecs=\"mp4a.40.2\""}"#.utf8))
        let rows = Extraction.filterOutDubbedAudio(streamManifest: [original, original, dubbed, unlabelled])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.compactMap { $0.audioTrack?.displayName }, ["English (Original)", "English (Original)"])
    }

    func testOriginalAudioMetadataMayOmitDefaultFlagWithoutBreakingPlayerDecode() throws {
        func response(_ label: String) throws -> InnerTube.VideoInfo {
            let object: [String: Any] = [
                "playabilityStatus": ["status": "OK"],
                "streamingData": ["adaptiveFormats": [[
                    "itag": 140, "url": "https://rr1.googlevideo.com/audio", "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"",
                    "audioTrack": ["displayName": label, "id": "en.4"]
                ]]]
            ]
            return try JSONDecoder().decode(InnerTube.VideoInfo.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let original = try XCTUnwrap(response("English (Original)").streamingData?.adaptiveFormats)
        XCTAssertNil(original.first?.audioTrack?.audioIsDefault)
        XCTAssertEqual(Extraction.filterOutDubbedAudio(streamManifest: original).count, 1)
        let unknown = try XCTUnwrap(response("English").streamingData?.adaptiveFormats)
        XCTAssertTrue(Extraction.filterOutDubbedAudio(streamManifest: unknown).isEmpty)
    }

    private static func audioTrackFormat(_ name: String, isDefault: Bool) throws -> InnerTube.StreamingData.Format {
        let object: [String: Any] = ["itag": 140, "url": "https://rr1.googlevideo.com/audio", "mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "audioTrack": ["displayName": name, "id": "en.4", "audioIsDefault": isDefault]]
        return try JSONDecoder().decode(InnerTube.StreamingData.Format.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testExtractVideoID() {
        let url = "https://www.youtube.com/watch?v=2lAe1cqCOXo"
        let videoID = Extraction.extractVideoID(from: url)
        XCTAssertEqual(videoID, "2lAe1cqCOXo")
    }

    func testDescramblerExcludesDRMFormatsBeforeMergingClients() throws {
        let json = #"""
        [
            {
                "formats": [
                    {"itag": 18, "mimeType": "video/mp4", "url": "https://example.com/protected-video", "drmFamilies": ["WIDEVINE"]}
                ],
                "adaptiveFormats": [
                    {"itag": 140, "mimeType": "audio/mp4", "url": "https://example.com/protected-audio", "drmFamilies": ["WIDEVINE"]}
                ]
            },
            {
                "formats": [
                    {"itag": 18, "mimeType": "video/mp4", "url": "https://example.com/clear-video"}
                ],
                "adaptiveFormats": [
                    {"itag": 140, "mimeType": "audio/mp4", "url": "https://example.com/clear-audio", "drmFamilies": []}
                ]
            }
        ]
        """#
        let responses = try JSONDecoder().decode([InnerTube.StreamingData].self, from: Data(json.utf8))
        let formats = responses.flatMap { Extraction.applyDescrambler(streamData: $0) }
        XCTAssertEqual(formats.map(\.itag), [18, 140])
        XCTAssertEqual(formats.compactMap(\.url), ["https://example.com/clear-video", "https://example.com/clear-audio"])
    }

    func testPlayabilityStatusReadsInterstitialErrors() throws {
        let cases: [(String, Extraction.InitialPlayerResponse.PlayabilityStatus.Status, [String])] = [
            (#"{"status":"LOGIN_REQUIRED","errorScreen":{"playerInterstitialRenderer":{"content":{"interstitialViewModel":{"title":{"content":"Private video"},"description":{"content":"Please sign in."}}}}}}"#, .loginRequired, ["Private video", "Please sign in."]),
            (#"{"status":"LOGIN_REQUIRED","reason":"Private video","messages":["This is a private video."]}"#, .loginRequired, ["Private video", "This is a private video."]),
            (#"{"status":"ERROR"}"#, .error, [])
        ]
        for (playabilityStatus, expectedStatus, expectedMessages) in cases {
            let html = "var ytInitialPlayerResponse = {\"playabilityStatus\":\(playabilityStatus)};"
            let (status, messages) = try Extraction.playabilityStatus(watchHTML: html)
            XCTAssertEqual(status, expectedStatus)
            XCTAssertEqual(messages, expectedMessages)
        }
    }

    func testJSURLUsesExtractedPlayerPath() throws {
        let html = #"ytcfg.set({"STS":20515});var ytInitialPlayerResponse = {};var ytplayer = {"config":{"assets":{"js":"/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js"}}};"#
        let jsURL = try Extraction.jsURL(html: html)
        XCTAssertEqual(jsURL, "https://youtube.com/s/player/6c5cb4f4/player_ias.vflset/en_US/base.js")
    }

    func testSignatureTimestampUsesExtractedValue() throws {
        let js = "signatureTimestamp:20515"
        let signatureTimestamp = Extraction.extractSignatureTimestamp(fromJS: js)
        XCTAssertEqual(signatureTimestamp, 20515)
    }

    func testSignatureTimestampReturnsNilWhenMissing() throws {
        let js = "const player = {}"
        let signatureTimestamp = Extraction.extractSignatureTimestamp(fromJS: js)
        XCTAssertNil(signatureTimestamp)
    }

    func testExtractYtCfgParsesEmbeddedEncryptedHostFlags() throws {
        let html = #"ytcfg.set({"VISITOR_DATA":"visitor","WEB_PLAYER_CONTEXT_CONFIGS":{"WEB_PLAYER_CONTEXT_CONFIG_ID_EMBEDDED_PLAYER":{"encryptedHostFlags":"test-flags"}}});"#
        let ytcfg = try Extraction.extractYtCfg(from: html)
        XCTAssertEqual(ytcfg.embeddedPlayerEncryptedHostFlags, "test-flags")
    }
    
}


@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
final class FastAudioTests: XCTestCase {
    func testSharedPlayerContextCoalescesAndInvalidates() async throws {
        let cache = FastAudioContextCache()
        let calls = FastAudioLoadCounter()
        let loader: () async throws -> FastAudioContextCache.Context = {
            let count = await calls.next()
            try await Task.sleep(nanoseconds: 25_000_000)
            let config = try JSONDecoder().decode(Extraction.YtCfg.self, from: Data("{}".utf8))
            return .init(source: "player-\(count)", config: config)
        }
        async let first = cache.value(loader: loader)
        async let second = cache.value(loader: loader)
        let values = try await [first, second]
        XCTAssertEqual(values.map(\.source), ["player-1", "player-1"])
        let count = await calls.count
        XCTAssertEqual(count, 1)
        await cache.invalidate()
        let reloaded = try await cache.value(loader: loader)
        XCTAssertEqual(reloaded.source, "player-2")
    }

    func testFormatCarriesAudioDurationWithoutCDNQueryParameter() throws {
        let data = Data(#"{"itag":140,"url":"https://rr1.googlevideo.com/videoplayback?id=audio","mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","approxDurationMs":"223080"}"#.utf8)
        let format = try JSONDecoder().decode(InnerTube.StreamingData.Format.self, from: data)
        let stream = try Stream(format: format)
        XCTAssertEqual(stream.duration, 223.08)
        XCTAssertTrue(stream.isNativelyPlayable)
    }

    func testFailedContextDoesNotPoisonNextSong() async throws {
        let cache = FastAudioContextCache()
        do {
            _ = try await cache.value { throw URLError(.cannotConnectToHost) }
            XCTFail("A failed fetch cannot be cached")
        } catch { }
        let recovered = try await cache.value {
            .init(source: "recovered", config: try JSONDecoder().decode(Extraction.YtCfg.self, from: Data("{}".utf8)))
        }
        XCTAssertEqual(recovered.source, "recovered")
    }
}
private actor FastAudioLoadCounter {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
