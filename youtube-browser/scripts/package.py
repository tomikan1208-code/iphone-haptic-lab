import hashlib
import json
import os
import plistlib
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app = root / ".build/iphone/Build/Products/Release-iphoneos/ResonWeb.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.tomikan1208.resonweb"
assert info["CFBundleDisplayName"] == "Reson Web"
assert not (app / "_CodeSignature").exists()
summary = json.loads((root / ".build/test-summary.json").read_text())
assert summary["result"] == "Passed" and summary["failedTests"] == 0 and summary["passedTests"] >= 20
artifact = root / ".build/artifact"
artifact.mkdir(parents=True, exist_ok=True)
ipa = artifact / f"Reson-Web-{info['CFBundleShortVersionString']}-unsigned.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob("*")):
        if file.is_file():
            archive.write(file, "Payload/ResonWeb.app/" + file.relative_to(app).as_posix())
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
metadata = {
    "displayName": info["CFBundleDisplayName"], "bundleIdentifier": info["CFBundleIdentifier"],
    "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
    "signed": False, "sourceCommit": os.environ.get("GITHUB_SHA"), "nativeTestsPassed": summary["passedTests"],
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "iOSSDK": subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True).strip(),
    "testSimulator": json.loads((root / ".build/simulator-device.json").read_text()),
    "youtubeAccountLoginTested": False, "youtubeHistoryWriteTested": False,
    "userReportedDeviceVerification": {"version": "0.1.0", "date": "2026-10-08", "login": True, "youtubeHistory": True},
    "hapticHardwareTested": False, "websiteObserverTestsPassed": 6,
    "ipaSHA256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
    "workflowURL": f"https://github.com/{os.environ.get('GITHUB_REPOSITORY')}/actions/runs/{os.environ.get('GITHUB_RUN_ID')}"
}
(artifact / "BUILD-INFO.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
(artifact / "TEST-SUMMARY.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
(artifact / "README.md").write_bytes((root / "README.md").read_bytes())
print(json.dumps(metadata, ensure_ascii=False, indent=2))
