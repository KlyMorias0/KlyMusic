#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-tests dist/screenshots
python3 scripts/ui-test-fixtures.py > build-tests/fixture.log 2>&1 &
KLY_FIXTURE_PID=$!
python3 scripts/sample-test-app.py > build-tests/sample.log 2>&1 &
KLY_SAMPLE_PID=$!
KLY_LOG_PID=''
finish() {
    kill "$KLY_FIXTURE_PID" 2>/dev/null || true
    kill "$KLY_SAMPLE_PID" 2>/dev/null || true
    if [ -n "$KLY_LOG_PID" ]; then kill "$KLY_LOG_PID" 2>/dev/null || true; fi
    if [ -d build-tests/Verification.xcresult ]; then
        xcrun xcresulttool export attachments --path build-tests/Verification.xcresult --output-path dist/screenshots || true
    fi
}
trap finish EXIT

KLY_DEVICE=$(python3 scripts/boot-test-simulator.py)
xcrun simctl spawn "$KLY_DEVICE" log stream --level debug --predicate 'subsystem == "com.klymusic.app"' > build-tests/playback.log 2>&1 &
KLY_LOG_PID=$!
xcodebuild -project ios/KlyMusic.xcodeproj -scheme KlyMusic \
    -destination "id=$KLY_DEVICE" -derivedDataPath build-tests/DerivedData \
    -parallel-testing-enabled NO -resultBundlePath build-tests/Verification.xcresult \
    -only-testing:KlyMusicTests \
    -only-testing:KlyMusicUITests/NavigationTests/testAppleStylePagesAndLibrary \
    -only-testing:KlyMusicUITests/NavigationTests/testNativeTabBarNavigationOffline \
    -only-testing:KlyMusicUITests/NavigationTests/testLyricsFollowAndLineSeeking \
    -only-testing:KlyMusicUITests/NavigationTests/testRedesignedScreensWithFixtures \
    -only-testing:KlyMusicUITests/NavigationTests/testPlayerMenuAndUpcomingQueue test
