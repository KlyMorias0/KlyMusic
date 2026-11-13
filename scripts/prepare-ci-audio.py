"""Reset the isolated Mac runner's audio service and retain a bounded route probe."""
import math
import hashlib
from pathlib import Path
import struct
import subprocess
import sys
import time
import wave


def run_probe(command, timeout):
    print('CI audio: ' + ' '.join(command), flush=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        print(f'CI audio exit: {result.returncode}', flush=True)
        for output in (result.stdout, result.stderr):
            if output:
                print(output, file=sys.stderr, flush=True)
    except subprocess.TimeoutExpired as error:
        print(f'CI audio probe timed out after {timeout}s: {error}', file=sys.stderr, flush=True)


package = Path('build-tests/BlackHole2ch-0.7.1.pkg')
package.parent.mkdir(parents=True, exist_ok=True)
# Pinned upstream package/checksum from the Homebrew blackhole-2ch cask. The driver
# stays on the disposable CI Mac; it is never linked into or bundled with the IPA.
subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--output', str(package),
                'https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg'], check=True, timeout=120)
assert hashlib.sha256(package.read_bytes()).hexdigest() == '57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf'
subprocess.run(['sudo', '-n', '/usr/sbin/installer', '-pkg', str(package), '-target', '/'], check=True, timeout=120)
run_probe(['sudo', '-n', 'killall', 'coreaudiod'], timeout=10)
time.sleep(3)
subprocess.run(['swift', 'scripts/select-ci-audio.swift'], check=True, timeout=60)
fixture = Path('build-tests/host-audio-probe.wav')
fixture.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(fixture), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(44100)
    output.writeframes(b''.join(struct.pack('<h', int(100 * math.sin(2 * math.pi * 440 * frame / 44100)))
                                for frame in range(11025)))
# This diagnoses the host route; the unchanged app tests remain the release gate.
run_probe(['/usr/bin/afplay', str(fixture)], timeout=25)
