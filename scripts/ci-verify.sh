#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build-tests dist/screenshots
python3 scripts/ui-test-fixtures.py > build-tests/fixture.log 2>&1 &
KLY_FIXTURE_PID=$!
python3 scripts/sample-test-app.py > build-tests/sample.log 2>&1 &
KLY_SAMPLE_PID=$!
KLY_LOG_PID=''
KLY_HOST_AUDIO_LOG_PID=''
KLY_SIM_AUDIO_LOG_PID=''
finish() {
    kill "$KLY_FIXTURE_PID" 2>/dev/null || true
    kill "$KLY_SAMPLE_PID" 2>/dev/null || true
    for task_log_pid in "$KLY_LOG_PID" "$KLY_HOST_AUDIO_LOG_PID" "$KLY_SIM_AUDIO_LOG_PID"; do
        if [ -n "$task_log_pid" ]; then kill "$task_log_pid" 2>/dev/null || true; fi
    done
    if [ -d build-tests/Verification.xcresult ]; then
        xcrun xcresulttool export attachments --path build-tests/Verification.xcresult --output-path dist/screenshots || true
    fi
}
trap finish EXIT

# Keep audio diagnostics separate from the app's playback metrics. Capture the
# host before boot so Simulator's audio route initialization is included.
KLY_AUDIO_PREDICATE='process == "coreaudiod" OR process == "audiomxd" OR process == "mediaserverd" OR process == "Simulator" OR process == "tccd" OR subsystem == "com.apple.TCC" OR subsystem CONTAINS[c] "audio" OR subsystem CONTAINS[c] "CoreMedia" OR subsystem CONTAINS[c] "MediaToolbox"'
/usr/bin/log stream --style compact --level info --predicate "$KLY_AUDIO_PREDICATE" > build-tests/host-audio.log 2>&1 &
KLY_HOST_AUDIO_LOG_PID=$!
KLY_DEVICE=$(python3 scripts/boot-test-simulator.py)
xcrun simctl spawn "$KLY_DEVICE" log stream --style compact --level info --predicate "$KLY_AUDIO_PREDICATE" > build-tests/simulator-audio.log 2>&1 &
KLY_SIM_AUDIO_LOG_PID=$!
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
