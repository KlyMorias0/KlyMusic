#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_root/scripts/ui-test-fixtures.py" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
KLY_DEVICE="${KLYMUSIC_TEST_DESTINATION:-id=$(python3 "$project_root/scripts/boot-test-simulator.py" 2>/dev/null || echo "platform=iOS Simulator,name=iPhone 16 Pro")}"
xcodebuild -project "$project_root/ios/KlyMusic.xcodeproj" -scheme KlyMusic \
  -destination "$KLY_DEVICE" \
  -derivedDataPath "${KLYMUSIC_BUILD_DIR:-$project_root/build-tests}" \
  -parallel-testing-enabled NO \
  -only-testing:KlyMusicTests \
  -only-testing:KlyMusicUITests/NavigationTests/testNativeTabBarNavigationOffline \
  -only-testing:KlyMusicUITests/NavigationTests/testLyricsFollowAndLineSeeking test
