#!/usr/bin/env python3
"""Check Lumina Release packaging and the approved offline capability boundary."""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

archive, settings_path = map(Path, sys.argv[1:])
app = archive / "Products/Applications/Lumina.app"
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "SA.Lumina"
assert "remote-notification" not in info.get("UIBackgroundModes", []), "Unused remote background mode"
for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
    assert info[key]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon", key
sizes = set()
for png in app.glob("*.png"):
    details = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(png)], text=True)
    dimensions = re.findall(r"pixel(?:Width|Height): (\d+)", details)
    sizes.add(tuple(map(int, dimensions)))
assert {(120, 120), (152, 152)} <= sizes, sizes
settings = next(item["buildSettings"] for item in json.loads(settings_path.read_text())
                if item["target"] == "Lumina")
assert settings["CONFIGURATION"] == "Release"
assert "UI_TESTING" not in settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")
executable = (app / info["CFBundleExecutable"]).read_bytes()
for marker in (b"--lumina-ui-qa", b"Isolated QA store", b"LUMINA_QA_ID"):
    assert marker not in executable, "Test isolation code present in production archive"
assert settings["ASSETCATALOG_COMPILER_APPICON_NAME"] == "AppIcon"
assert not settings.get("ICLOUD_CONTAINER_ENVIRONMENT"), "Unused iCloud environment setting"
entitlements = Path(settings["SRCROOT"]) / settings["CODE_SIGN_ENTITLEMENTS"]
source = plistlib.loads(entitlements.read_bytes())
expected_groups = ["group.SA.Lumina"]
assert source == {"com.apple.security.application-groups": expected_groups}, "Unexpected source capabilities"
privacy = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
assert privacy["NSPrivacyTracking"] is False
reasons = next(entry["NSPrivacyAccessedAPITypeReasons"] for entry in privacy["NSPrivacyAccessedAPITypes"]
               if entry["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults")
assert {"CA92.1", "1C8F.1"} <= set(reasons)
print("PASS: iPhone/iPad PNGs, both CFBundleIconName entries, offline Release capabilities and preferences privacy manifest.")
signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)],
                        capture_output=True)
if signed.returncode == 0:
    actual = plistlib.loads(signed.stdout)
    assert actual.get("com.apple.security.application-groups") == expected_groups, "App group changed"
    for key in actual:
        assert not key.startswith(("com.apple.developer.icloud", "com.apple.developer.ubiquity")), "Unused cloud entitlement"
        assert key not in {"aps-environment", "com.apple.developer.aps-environment"}, "Unused APNs entitlement"
    print("PASS: Offline capability boundary and retained app group embedded in code signature.")
else:
    print("UNVERIFIED: unsigned archive; distribution signing and embedded entitlements still require verification.")
