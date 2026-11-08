"""Boot the CI simulator with bounded CoreSimulator startup and diagnostics."""
import json
import subprocess
import sys


def simctl(*arguments, timeout=75):
    print('Simulator: ' + ' '.join(arguments), file=sys.stderr, flush=True)
    return subprocess.run(['xcrun', 'simctl', *arguments], check=True, capture_output=True,
                          text=True, timeout=timeout).stdout


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

devices = [device for runtime, entries in groups.items() if 'iOS-26-' in runtime
           for device in entries if device['name'].startswith('iPhone') and device['isAvailable']]
devices.sort(key=lambda device: (device['name'] != 'iPhone 17 Pro', device['name']))
if not devices:
    raise SystemExit('An iOS 26 iPhone simulator is required.')
device = devices[0]
if device['state'] != 'Booted':
    simctl('boot', device['udid'])
simctl('bootstatus', device['udid'], '-b', timeout=120)
simctl('status_bar', device['udid'], 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100', timeout=20)
print(device['udid'])
