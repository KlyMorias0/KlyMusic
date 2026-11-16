"""Capture bounded app and audio-service diagnostics for simulator UI stalls."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time


OUTPUT = Path('build-tests/samples')
APP_NAMES = {'KlyMusic'}
# Include both host and simulator services when present. Their executable paths
# and parent PIDs in processes.jsonl distinguish the two environments.
SERVICE_NAMES = {'Simulator', 'coreaudiod', 'audiomxd', 'mediaserverd'}
APP_INTERVAL = 20
SERVICE_INTERVAL = 60


@dataclass(frozen=True)
class Process:
    pid: int
    parent_pid: int
    uid: int
    executable: str

    @property
    def name(self):
        return Path(self.executable).name


def selected_processes():
    try:
        result = subprocess.run(['/bin/ps', '-ww', '-axo', 'pid=,ppid=,uid=,comm='],
                                capture_output=True, text=True, timeout=5, check=True)
    except (OSError, subprocess.SubprocessError) as error:
        print(f'Process inventory unavailable: {error}', flush=True)
        return []
    processes = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) != 4 or Path(fields[3]).name not in APP_NAMES | SERVICE_NAMES:
            continue
        try:
            processes.append(Process(int(fields[0]), int(fields[1]), int(fields[2]), fields[3]))
        except ValueError:
            print(f'Ignoring malformed process inventory row: {line}', flush=True)
    return processes


def capture(process):
    target = OUTPUT / f'{time.time_ns()}-{process.name}-{process.pid}.txt'
    command = ['/usr/bin/sample', str(process.pid), '1', '20', '-file', str(target)]
    if process.uid != os.getuid():
        # System services require elevated inspection; -n must never prompt.
        command = ['sudo', '-n', *command]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        if result.returncode:
            detail = (result.stderr or result.stdout)[-2000:].strip()
            print(f'Sample {process.name} ({process.pid}) exited {result.returncode}: {detail}', flush=True)
    except (OSError, subprocess.SubprocessError) as error:
        print(f'Sample {process.name} ({process.pid}) unavailable: {error}', flush=True)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    next_services = 0.0
    # Sampling does not gate tests; each invocation is bounded, and service
    # collection is less frequent to limit overhead on the runner.
    with ThreadPoolExecutor(max_workers=4) as pool:
        while not stopped.is_set():
            started = time.monotonic()
            processes = selected_processes()
            record = {'timestamp_ns': time.time_ns(), 'processes': [asdict(p) for p in processes]}
            with (OUTPUT / 'processes.jsonl').open('a', encoding='utf-8') as inventory:
                inventory.write(json.dumps(record) + '\n')
            include_services = started >= next_services
            if include_services:
                next_services = started + SERVICE_INTERVAL
            targets = [p for p in processes if p.name in APP_NAMES or include_services]
            list(pool.map(capture, targets))
            stopped.wait(max(0, APP_INTERVAL - (time.monotonic() - started)))


if __name__ == '__main__':
    main()
