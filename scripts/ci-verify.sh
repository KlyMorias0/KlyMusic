#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-tests dist/screenshots
python3 scripts/ui-test-fixtures.py > build-tests/fixture.log 2>&1 &
KLY_FIXTURE_PID=$!
finish() {
    kill "$KLY_FIXTURE_PID" 2>/dev/null || true
    if [ -d build-tests/Verification.xcresult ]; then
        xcrun xcresulttool export attachments --path build-tests/Verification.xcresult --output-path dist/screenshots || true
    fi
}
trap finish EXIT

KLY_DEVICE=$(python3 scripts/boot-test-simulator.py)
xcodebuild -project ios/KlyMusic.xcodeproj -scheme KlyMusic \
    -destination "id=$KLY_DEVICE" -derivedDataPath build-tests/DerivedData \
    -parallel-testing-enabled NO -resultBundlePath build-tests/Verification.xcresult \
    -only-testing:KlyMusicTests \
    -only-testing:KlyMusicUITests/NavigationTests/testNativeTabBarNavigationOffline \
    -only-testing:KlyMusicUITests/NavigationTests/testLyricsFollowAndLineSeeking \
    -only-testing:KlyMusicUITests/NavigationTests/testRedesignedScreensWithFixtures \
    -only-testing:KlyMusicUITests/NavigationTests/testPlayerMenuAndUpcomingQueue test
