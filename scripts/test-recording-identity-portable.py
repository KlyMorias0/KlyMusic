#!/usr/bin/env python3
"""Run the production identity helper and its real synchronous XCTest cases.
This does not compile the iOS app or validate playable media.
"""
from pathlib import Path
import argparse,re,subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--swiftc',default='swiftc')
parser.add_argument('--output',default='build/2.13.0/portable-identity')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
models=(root/'ios/KlyMusic/Models.swift').read_text()
tests=(root/'ios/KlyMusicTests/CoreTests.swift').read_text()
track=models[models.index('struct Track:'):models.index('struct MusicCollection:')]
identity=models[models.index('enum RecordingIdentity {'):models.index('@Model final class SavedTrack')]
methods=[]
names=[]
for match in re.finditer(r'    func (testGeneral\w+)\(',tests):
 start=match.start()
 opening=tests.index('{',match.end())
 depth=1; end=opening+1
 while depth:
  if tests[end]=='{':depth+=1
  elif tests[end]=='}':depth-=1
  end+=1
 names.append(match.group(1));methods.append(tests[start:end])
assert len(names)>=5,names
section='final class PortableIdentityTests: XCTestCase {\n'+'\n'.join(methods)+'\n}\n'
suite='\nXCTMain([testCase([\n'+',\n'.join('    ("'+n+'", PortableIdentityTests.'+n+')' for n in names)+'\n])])\n'
output=root/args.output
output.parent.mkdir(parents=True,exist_ok=True)
source=output.with_suffix('.swift')
source.write_text('import Foundation\nimport XCTest\n'+track+identity+section+suite)
subprocess.run([args.swiftc,'-swift-version','5',str(source),'-o',str(output)],check=True,cwd=root)
subprocess.run([str(output)],check=True,cwd=root)
print(f'Portable identity verification: {len(names)} real XCTest methods; no iOS build or live audio claim.')
