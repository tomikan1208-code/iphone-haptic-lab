#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/artifact
xcodebuild -version
plutil -lint HapticLab/Info.plist HapticLab.xcodeproj/project.pbxproj
if ! xcodebuild build \
  -project HapticLab.xcodeproj -scheme HapticLab -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build/ios \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  > .build/build-ios.log 2>&1; then
  tail -n 120 .build/build-ios.log
  exit 1
fi

app='.build/ios/Build/Products/Release-iphoneos/HapticLab.app'
test -f "$app/HapticLab"
test -f "$app/Info.plist"
plutil -lint "$app/Info.plist"
architectures="$(xcrun lipo -archs "$app/HapticLab")"
if [[ "$architectures" != 'arm64' ]]; then
  echo "Expected a physical iPhone arm64 build, got: $architectures"
  exit 1
fi

staging="$(mktemp -d "$PWD/.build/package.XXXXXX")"
mkdir -p "$staging/Payload"
cp -R "$app" "$staging/Payload/"
ditto -c -k --keepParent "$staging/Payload" .build/artifact/HapticLab-unsigned.ipa
cp docs/INSTALL-WINDOWS.md .build/artifact/INSTALL-WINDOWS.md
cp docs/MUSIC.md docs/GOOGLE-LOGIN.md .build/artifact/
cp docs/PC-SERVER.md .build/artifact/
(cd .build/artifact && shasum -a 256 HapticLab-unsigned.ipa > SHA256SUMS.txt)
echo 'Physical iPhone build passed. IPA is unsigned and must be signed locally using Sideloadly.'
