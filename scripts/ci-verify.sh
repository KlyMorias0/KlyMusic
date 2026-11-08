#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-tests dist/screenshots
python3 scripts/ui-test-fixtures.py > build-tests/fixture.log 2>&1 &
KLY_FIXTURE_PID=$!
trap 'kill "$KLY_FIXTURE_PID" 2>/dev/null || true' EXIT

xcrun simctl list devices available --json > build-tests/devices.json
KLY_DEVICE=$(python3 - <<'PY'
import json
with open('build-tests/devices.json') as file:
    groups = json.load(file)['devices']
devices = [d for runtime, entries in groups.items() if 'iOS-26-' in runtime
           for d in entries if d['name'].startswith('iPhone') and d['isAvailable']]
devices.sort(key=lambda d: (d['name'] != 'iPhone 17 Pro', d['name']))
if not devices: raise SystemExit('An iOS 26 iPhone simulator is required.')
print(devices[0]['udid'])
PY
)
if ! xcrun simctl list devices booted | /usr/bin/grep -q "$KLY_DEVICE"; then
    xcrun simctl boot "$KLY_DEVICE"
fi
xcrun simctl bootstatus "$KLY_DEVICE" -b
xcrun simctl status_bar "$KLY_DEVICE" override --time '9:41' --batteryState charged --batteryLevel 100
xcodebuild -project ios/KlyMusic.xcodeproj -scheme KlyMusic \
    -destination "id=$KLY_DEVICE" -derivedDataPath build-tests/DerivedData \
    -parallel-testing-enabled NO -resultBundlePath build-tests/Verification.xcresult \
    -only-testing:KlyMusicTests \
    -only-testing:KlyMusicUITests/NavigationTests/testNativeTabBarNavigationOffline \
    -only-testing:KlyMusicUITests/NavigationTests/testLyricsFollowAndLineSeeking \
    -only-testing:KlyMusicUITests/NavigationTests/testRedesignedScreensWithFixtures test
xcrun xcresulttool export attachments --path build-tests/Verification.xcresult --output-path dist/screenshots
