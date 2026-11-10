#!/usr/bin/env python3
"""Run real audio metadata/availability code and real XCTest fixtures on Linux.
No player requests, JavaScript signatures, CDN playback or iOS app are tested.
"""
from pathlib import Path
import argparse,re,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--swiftc',default='swiftc')
parser.add_argument('--output',default='build/2.13.0/portable-audio-metadata')
args=parser.parse_args();root=Path(__file__).resolve().parents[1]
pkg=root/'ios/Packages/YouTubeKit'
inner=(pkg/'Sources/YouTubeKit/InnerTube.swift').read_text()
types=inner[inner.index('    struct VideoInfo:'):inner.index('    private struct PlaybackContext:')]
extract=(pkg/'Sources/YouTubeKit/Extraction.swift').read_text()
filtercode=extract[extract.index('    class func filterOutDubbedAudio'):extract.index('    /// Breaks up the data',extract.index('    class func filterOutDubbedAudio'))]
tests=(pkg/'Tests/YouTubeKitTests/ExtractionTests.swift').read_text()
fixtures=tests[tests.index('    func testOriginalAudioMarker'):tests.index('    func testExtractVideoID')]
names=re.findall(r'    func (test\w+)\(',fixtures);assert len(names)==5,names
source='import Foundation\nimport XCTest\nenum InnerTube {\n'+types+'}\nclass Extraction {\n'+filtercode+'}\nfinal class PortableAudioMetadataTests: XCTestCase {\n'+fixtures+'}\n'
yt=(pkg/'Sources/YouTubeKit/YouTube.swift').read_text()
state=yt[yt.index('actor AudioAvailabilityState {'):]
errors=(pkg/'Sources/YouTubeKit/Errors.swift').read_text()
a=errors.index('public enum AudioStreamFailure:');error=errors[a:]
case=(pkg/'Tests/YouTubeKitTests/FastAudioFallbackTests.swift').read_text()
a=case.index('    func testAuthenticationFailureRemainsDistinct')
methods=case[a:case.rindex('}')]
asyncnames=re.findall(r'    func (test\w+)\(',methods);assert len(asyncnames)==2
source+=error+'\n'+state+'\nfinal class PortableAvailabilityTests: XCTestCase {\n'+methods+'}\n'
source+='\nXCTMain([testCase([\n'+',\n'.join('("'+n+'", PortableAudioMetadataTests.'+n+')' for n in names)+'\n]),testCase([\n'+',\n'.join('("'+n+'", asyncTest(PortableAvailabilityTests.'+n+'))' for n in asyncnames)+'\n])])\n'
output=root/args.output;output.parent.mkdir(parents=True,exist_ok=True)
file=output.with_suffix('.swift');file.write_text(source)
subprocess.run([args.swiftc,'-swift-version','5',str(file),'-o',str(output)],check=True,cwd=root)
subprocess.run([str(output)],check=True,cwd=root)
print('Portable audio metadata verification: 7 real tests; no extraction/network/iOS build claim.')
