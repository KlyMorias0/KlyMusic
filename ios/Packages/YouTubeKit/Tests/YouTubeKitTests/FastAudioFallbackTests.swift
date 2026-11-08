import XCTest
@testable import YouTubeKit

@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
extension FastAudioTests {
    func testFastAudioContextFailureContinuesThroughFullExtractor() async throws {
        let value = try await AudioExtractionFallback.value(fast: { () async throws -> Int? in
            throw URLError(.timedOut)
        }, fallback: { 7 })
        XCTAssertEqual(value, 7)
    }

    func testFastAudioWinnerDoesNotStartFullExtractor() async throws {
        let value = try await AudioExtractionFallback.value(fast: { 3 }, fallback: {
            XCTFail("A valid fast stream must not trigger the full extractor")
            return 7
        })
        XCTAssertEqual(value, 3)
    }

    func testFastAudioNoWinnerUsesFullExtractor() async throws {
        let value = try await AudioExtractionFallback.value(fast: { nil as Int? }, fallback: { 7 })
        XCTAssertEqual(value, 7)
    }

    func testCancelledFastAudioDoesNotStartFullExtractor() async {
        let task = Task {
            try await AudioExtractionFallback.value(fast: { () async throws -> Int? in
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return nil
            }, fallback: {
                XCTFail("Cancelled playback must not start another extraction")
                return 7
            })
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    func testCancellingOneContextWaiterDoesNotCancelAnother() async throws {
        let cache = FastAudioContextCache()
        let gate = FastAudioContextGate()
        let canceled = expectation(description: "First waiter releases before shared fetch finishes")
        let first = Task {
            do { _ = try await cache.value { await gate.wait() }; XCTFail("Expected cancellation") }
            catch is CancellationError { canceled.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        try await waitForContextWaiters(1, in: cache)
        let second = Task { try await cache.value { XCTFail("Context fetch should be shared"); return Self.audioContext("unexpected") } }
        try await waitForContextWaiters(2, in: cache)
        first.cancel()
        await fulfillment(of: [canceled], timeout: 1)
        let remaining = await cache.waiterCount()
        XCTAssertEqual(remaining, 1)
        await gate.release(Self.audioContext("shared"))
        let context = try await second.value
        XCTAssertEqual(context.source, "shared")
        await first.value
        let cached = try await cache.value { XCTFail("Shared result should remain cached"); return Self.audioContext("unexpected") }
        XCTAssertEqual(cached.source, "shared")
    }

    func testCancelledLastContextWaiterReleasesAndLateCompletionCannotReplaceNewContext() async throws {
        let cache = FastAudioContextCache()
        let gate = FastAudioContextGate()
        let canceled = expectation(description: "Last canceled waiter releases immediately")
        let old = Task {
            do { _ = try await cache.value { await gate.wait() }; XCTFail("Expected cancellation") }
            catch is CancellationError { canceled.fulfill() }
            catch { XCTFail("Unexpected error: \(error)") }
        }
        try await waitForContextWaiters(1, in: cache)
        old.cancel()
        await fulfillment(of: [canceled], timeout: 1)
        let loaded = expectation(description: "Next song starts a fresh request while old loader is suspended")
        let newer = Task {
            let value = try await cache.value { Self.audioContext("new") }
            XCTAssertEqual(value.source, "new")
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 1)
        await gate.release(Self.audioContext("old"))
        await old.value
        try await newer.value
        // Wait for the deliberately non-cooperative old fetch to report its late completion.
        for _ in 0..<1000 {
            if await cache.completionCount() == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let completions = await cache.completionCount()
        XCTAssertEqual(completions, 2)
        let current = try await cache.value { XCTFail("New context should be cached"); return Self.audioContext("unexpected") }
        XCTAssertEqual(current.source, "new")
    }

    private func waitForContextWaiters(_ expected: Int, in cache: FastAudioContextCache) async throws {
        for _ in 0..<1000 {
            if await cache.waiterCount() == expected { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Context waiters were not registered")
    }
    private static func audioContext(_ source: String) -> FastAudioContextCache.Context {
        .init(source: source, config: try! JSONDecoder().decode(Extraction.YtCfg.self, from: Data("{}".utf8)))
    }

}


@available(iOS 15.0, watchOS 8.0, tvOS 15.0, macOS 12.0, *)
private actor FastAudioContextGate {
    private var continuation: CheckedContinuation<FastAudioContextCache.Context, Never>?
    private var result: FastAudioContextCache.Context?
    func wait() async -> FastAudioContextCache.Context {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ context: FastAudioContextCache.Context) {
        result = context
        continuation?.resume(returning: context); continuation = nil
    }
}
