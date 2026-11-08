#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_root/scripts/ui-test-fixtures.py" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
xcodebuild -project "$project_root/ios/KlyMusic.xcodeproj" -scheme KlyMusic \
  -destination "${KLYMUSIC_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" \
  -derivedDataPath "${KLYMUSIC_BUILD_DIR:-$project_root/build-tests}" \
  -parallel-testing-enabled NO \
  -only-testing:KlyMusicTests \
  -only-testing:KlyMusicUITests/NavigationTests/testNativeTabBarNavigationOffline \
  -only-testing:KlyMusicUITests/NavigationTests/testLyricsFollowAndLineSeeking test
