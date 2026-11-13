"""Boot the CI simulator with bounded CoreSimulator startup and diagnostics."""
import json
from pathlib import Path
import subprocess
import sys


def simctl(*arguments, timeout=75):
    print('Simulator: ' + ' '.join(arguments), file=sys.stderr, flush=True)
    try:
        return subprocess.run(['xcrun', 'simctl', *arguments], check=True, capture_output=True,
                              text=True, timeout=timeout).stdout
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
        for output in (error.stdout, error.stderr):
            if output:
                if isinstance(output, bytes):
                    output = output.decode('utf-8', errors='replace')
                print(output, file=sys.stderr, end='' if output.endswith('\n') else '\n', flush=True)
        raise


for attempt in range(2):
    try:
        groups = json.loads(simctl('list', 'devices', 'available', '--json'))['devices']
        break
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, json.JSONDecodeError):
        if attempt:
            raise
        print('CoreSimulator startup stalled; restarting the isolated CI service once.', file=sys.stderr, flush=True)
        subprocess.run(['killall', '-9', 'com.apple.CoreSimulator.CoreSimulatorService'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)

ios_runtimes = sorted([r for r in groups.keys() if 'iOS' in r], reverse=True)
devices = []
for runtime in ios_runtimes:
    candidates = [device for device in groups[runtime] if device.get('name', '').startswith('iPhone') and device.get('isAvailable', False)]
    if candidates:
        candidates.sort(key=lambda d: (0 if 'Pro' in d.get('name', '') else 1, d.get('name', '')))
        devices.extend(candidates)
        break

if not devices:
    raise SystemExit('No available iPhone simulator found.')
device = devices[0]
if device['state'] != 'Booted':
    simctl('boot', device['udid'])
# Simulator.app hosts the Mac audio route used by media in the simulator.
# Start the app from the selected Xcode before playback tests use that route.
developer = subprocess.run(['xcode-select', '-p'], check=True, capture_output=True,
                           text=True, timeout=10).stdout.strip()
simulator_app = Path(developer) / 'Applications/Simulator.app'
print(f'Starting Simulator audio host: {simulator_app}', file=sys.stderr, flush=True)
subprocess.run(['open', '-a', str(simulator_app), '--args', '-CurrentDeviceUDID', device['udid']],
               check=True, stdout=sys.stderr, stderr=sys.stderr, timeout=30)
simctl('bootstatus', device['udid'], '-b', timeout=300)
try:
    simctl('status_bar', device['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', timeout=20)
except Exception as e:
    print(f'Warning: status_bar override ignored: {e}', file=sys.stderr, flush=True)
print(device['udid'])
