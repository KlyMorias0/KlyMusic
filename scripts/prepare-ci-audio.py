"""Reset the isolated Mac runner's audio service and retain a bounded route probe."""
import math
from pathlib import Path
import struct
import subprocess
import sys
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


run_probe(['sudo', '-n', 'killall', 'coreaudiod'], timeout=10)
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
