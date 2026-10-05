#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node scripts/select-simulator.mjs
device="$(cat .build/simulator-id.txt)"
mkdir -p .build/screenshots
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
if ! xcodebuild test \
  -project HapticLab.xcodeproj -scheme HapticLab -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath .build/simulator \
  -resultBundlePath .build/TestResults.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  > .build/test-ios.log 2>&1; then
  tail -n 140 .build/test-ios.log
  exit 1
fi

if ! xcrun xcresulttool export attachments --path .build/TestResults.xcresult --output-path .build/screenshots; then
  echo 'Attachment export was unavailable; creating a launch screenshot instead.'
fi
xcrun simctl install "$device" .build/simulator/Build/Products/Debug-iphonesimulator/HapticLab.app
xcrun simctl launch "$device" com.tomikan1208.hapticlab
sleep 2
xcrun simctl io "$device" screenshot .build/screenshots/gallery-launch.png
cp .build/simulator-device.json .build/screenshots/device.json
grep -E 'Test (Case|Suite).*passed|Executed .* tests|TEST SUCCEEDED' .build/test-ios.log | tail -n 20

