#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${KLYMUSIC_BUILD_DIR:-$project_root/build}"
mkdir -p "$build_dir" "$project_root/dist"
xcodebuild -project "$project_root/ios/KlyMusic.xcodeproj" -scheme KlyMusic \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_dir" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
package_dir="$(mktemp -d "$build_dir/package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
cp -R "$build_dir/Build/Products/Release-iphoneos/KlyMusic.app" "$package_dir/Payload/"
find "$package_dir/Payload" -name _CodeSignature -type d -prune -exec rm -rf {} +
rm -f "$project_root/dist/KlyMusic-unsigned.ipa"
(cd "$package_dir" && /usr/bin/zip -qr "$project_root/dist/KlyMusic-unsigned.ipa" Payload)
(cd "$project_root/dist" && shasum -a 256 KlyMusic-unsigned.ipa > SHA256.txt)
echo "IPA: $project_root/dist/KlyMusic-unsigned.ipa"
