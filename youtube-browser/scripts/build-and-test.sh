#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/screenshots
node --test scripts/test-playback-observation.mjs
python3 -m venv .build/fixture-venv
.build/fixture-venv/bin/python -m pip install imageio-ffmpeg==0.6.0
.build/fixture-venv/bin/python scripts/generate-fixture.py
python3 -u scripts/serve-fixture.py > .build/fixture-server.log 2>&1 &
fixture_server=$!
trap 'kill "$fixture_server" 2>/dev/null || true' EXIT
node scripts/generate-project.mjs
node scripts/generate-icons.mjs
if ! xcodebuild build -project ResonWeb.xcodeproj -scheme ResonWeb -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/iphone \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > .build/build.log 2>&1; then
  tail -n 100 .build/build.log
  exit 1
fi
node scripts/select-simulator.mjs
device="$(cat .build/simulator-id.txt)"
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b
xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
result=0
xcodebuild test -project ResonWeb.xcodeproj -scheme ResonWeb -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath .build/simulator \
  -resultBundlePath .build/TestResults.xcresult -parallel-testing-enabled NO \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > .build/test.log 2>&1 || result=$?
xcrun xcresulttool get test-results summary --path .build/TestResults.xcresult > .build/test-summary.json || true
xcrun xcresulttool export attachments --path .build/TestResults.xcresult --output-path .build/screenshots || true
cp .build/simulator-device.json .build/screenshots/device.json
cp .build/fixture-server.log .build/screenshots/fixture-server.log
if [[ "$result" != '0' ]]; then
  mkdir -p .build/diagnostics
  cp "$HOME"/Library/Logs/DiagnosticReports/ResonWeb* .build/diagnostics/ 2>/dev/null || true
  xcrun simctl spawn "$device" log show --style compact --last 5m --predicate 'process == "ResonWeb"' > .build/diagnostics/runtime.log 2>&1 || true
  tail -n 120 .build/test.log
  exit "$result"
fi
python3 scripts/package.py
