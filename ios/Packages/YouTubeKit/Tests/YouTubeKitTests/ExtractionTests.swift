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
