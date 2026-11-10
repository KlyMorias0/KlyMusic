#!/usr/bin/env python3
"""Run real resolver/cache/parser XCTest methods on Swift for Linux.

Extracts production code without rewriting its control flow. FoundationNetworking
replaces the Darwin networking import. Locale/localization are fixed adapters.
Only unexercised CDN audio extractors are replaced by throwing sentinels: these
checks use the production StreamLoader injection and never validate real audio,
YouTube extraction, AVPlayer, SwiftUI, signing, or an iOS device build.
"""
from pathlib import Path
import argparse
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--swiftc', default='swiftc')
parser.add_argument('--output', default='build/2.13.0/portable-resolver')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
models = (root / 'ios/KlyMusic/Models.swift').read_text()
api = (root / 'ios/KlyMusic/API.swift').read_text()
catalog = (root / 'ios/KlyMusic/NativeCatalog.swift').read_text()
tests = (root / 'ios/KlyMusicTests/CoreTests.swift').read_text()
errors = (root / 'ios/Packages/YouTubeKit/Sources/YouTubeKit/Errors.swift').read_text()


def block(source, signature):
    """Extract selected balanced source declarations, preserving the exact text."""
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == '{':
            depth += 1
        elif source[end] == '}':
            depth -= 1
        end += 1
    return source[start:end]


names = [
    'testResolverTriesPlayableCopiesBeyondFirstThreeAndReusesVerifiedStream',
    'testResolverContinuesGeneralQueriesAfterFirstMatchedCopyFails',
    'testResolverDistinguishesProviderAuthenticationFromNoMatch',
    'testPlaybackRacePreservesActionableProviderFailureAcrossEmptyFallbacks',
    'testYouTubeSearchParserRetainsUnlabelledCollaborationCredits',
]
methods = [block(tests, '    func ' + name + '(') for name in names]
helpers = [block(tests, '    private static func ' + name + '(') for name in ['resolverAsset', 'catalogRows']]
protocol = block(tests, 'private final class CatalogResponseProtocol:')
recorder = block(tests, 'private actor PlaybackCallRecorder {')
# Entire portable model prefix, including the actual RecordingIdentity implementation.
model_code = models[models.index('struct Track:'):models.index('@Model final class SavedTrack')]
api_code = api[api.index('enum PlaybackRace {'):api.index('actor API {')]
header = catalog[catalog.index('actor NativeCatalog {'):catalog.index('    init(')]
# Every selected method is copied verbatim. No mock matching/racing/cache logic.
method_signatures = [
    '    init(', '    func resolve(', '    private func resolveStage(',
    '    private func resolveCandidates(', '    private func resolveAsset(',
    '    private func matchedCandidates(', '    func invalidatePlayback(',
    '    static func validCandidate(', '    static func validResolvedDuration(',
    '    static func candidateQueries(', '    private func recordingDetails(',
    '    private func youtubeStream(', '    private func youtubeSearch(',
    '    static func youtubeTracks(', '    private func saavnSearch(',
    '    private func saavnStream(', '    private func trace(', '    private func lookup(',
    '    private func saavn(', '    private func json(', '    private static func appleTrack(',
    '    static func allowedMediaURL(', '    static func normalized(',
    '    static func canonical(', '    static func durationCompatible(',
    '    static func mediaDuration(', '    static func streamDuration(',
    '    static func sameRecordingIdentity(', '    static func match(',
    '    private static func art(', '    private static func number(',
    '    private static func unescape(', '    private static func at(',
    '    private static func nodes(', '    private static func firstString(',
    '    private static func values(',
]
native_code = header + '\n\n'.join(block(catalog, signature) for signature in method_signatures)
native_code += '''
    // Linux-only sentinels: these tests must inject all stream loaders.
    private func loadYoutubeStream(_ id: String, quality: String, expectedDuration: Double) async throws -> PlaybackAsset {
        XCTFail("Portable resolver test unexpectedly entered real CDN extraction")
        throw PortableScopeError.realAudioUnavailable
    }
    private func loadSaavnStream(_ id: String, quality: String, duration: Double) async throws -> PlaybackAsset {
        XCTFail("Portable resolver test unexpectedly entered real CDN extraction")
        throw PortableScopeError.realAudioUnavailable
    }
}
'''
adapters = '''
// Harness-only platform adapters. They do not implement resolver behavior.
func L(_ value: String) -> String { value }
struct ListeningLocale {
    static let current = ListeningLocale()
    let cacheKey = "portable-resolver-en-us"
    let languageCode = "en"
    let countryCode = "us"
}
enum PortableScopeError: Error { case realAudioUnavailable }
// Darwin has a defaulted diskPath parameter; Linux requires it explicitly.
extension URLCache {
    convenience init(memoryCapacity: Int, diskCapacity: Int) {
        self.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: nil)
    }
}
'''
error_code = '\n'.join(block(errors, signature) for signature in [
    'public enum YouTubeKitError:', 'public enum AudioStreamFailure:',
])
section = 'final class PortableResolverTests: XCTestCase {\n' + '\n'.join(methods + helpers) + '\n}\n'
suite_rows = []
for name, method in zip(names, methods):
    reference = 'PortableResolverTests.' + name
    if re.search(r'\) async(?: throws)? \{', method):
        reference = 'asyncTest(' + reference + ')'
    suite_rows.append('    ("' + name + '", ' + reference + ')')
suite = '\nXCTMain([testCase([\n' + ',\n'.join(suite_rows) + '\n])])\n'
output = root / args.output
output.parent.mkdir(parents=True, exist_ok=True)
source = output.with_suffix('.swift')
source.write_text('\n'.join(['import Foundation\nimport FoundationNetworking\nimport XCTest', adapters, error_code, model_code, api_code, native_code, recorder, protocol, section, suite]))
subprocess.run([args.swiftc, '-swift-version', '5', '-D', 'DEBUG', str(source), '-o', str(output)], check=True, cwd=root)
subprocess.run([str(output)], check=True, cwd=root)
print(f'Portable resolver verification: {len(names)} actual XCTest methods; injected media only; no iOS build or live audio claim.')
