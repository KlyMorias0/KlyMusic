"""Capture bounded main-thread diagnostics for simulator UI timeouts."""
from pathlib import Path
import subprocess
import time

output = Path('build-tests/samples')
output.mkdir(parents=True, exist_ok=True)
while True:
    result = subprocess.run(['pgrep', '-x', 'KlyMusic'], capture_output=True, text=True, timeout=5)
    for pid in result.stdout.split():
        try:
            subprocess.run(['sample', pid, '1', '20', '-file', str(output / f'{time.time_ns()}-{pid}.txt')],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        except subprocess.TimeoutExpired:
            pass
    time.sleep(20)
