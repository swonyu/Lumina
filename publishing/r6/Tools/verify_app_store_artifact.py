#!/usr/bin/env python3
"""Read-only iOS signed-artifact inspection. Never signs, builds, or submits.

An ARTIFACT_CHECKS_PASSED result is deliberately narrower than submission
readiness or Apple acceptance. See README.txt for the supported input contract.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import struct
import subprocess
import tempfile
from typing import Any, Callable
import zlib

UTC = dt.timezone.utc
MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_BUNDLE_BYTES = 1024 * 1024 * 1024
MAX_FILES = 20000
QA_MARKERS = (b"--lumina-ui-qa", b"Isolated QA store", b"LUMINA_QA_ID")


class ValidationError(Exception):
    pass


def read_bytes(path: Path, limit: int = 8 * 1024 * 1024) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValidationError(f"Missing, nonregular, or symbolic-link file: {path.name}")
    if path.stat().st_size > limit:
        raise ValidationError(f"File exceeds bounded inspection limit: {path.name}")
    with path.open("rb") as handle:
        data = handle.read(limit + 1)
    if len(data) > limit:
        raise ValidationError(f"File grew beyond inspection limit: {path.name}")
    return data


def plist_dict(data: bytes) -> dict[str, Any]:
    try:
        value = plistlib.loads(data)
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        raise ValidationError("Unreadable property list") from error
    if not isinstance(value, dict):
        raise ValidationError("Property list root must be a dictionary")
    return value


def artifact_app(path: Path) -> tuple[Path, Path]:
    artifact = path.expanduser().resolve(strict=True)
    if not artifact.is_dir():
        raise ValidationError("Input must be an existing .app or .xcarchive directory; IPA is unsupported")
    if artifact.suffix == ".app":
        return artifact, artifact
    if artifact.suffix != ".xcarchive":
        raise ValidationError("Input must be an explicit .app or .xcarchive directory")
    apps = sorted((artifact / "Products" / "Applications").glob("*.app"))
    if len(apps) != 1 or not apps[0].is_dir() or apps[0].is_symlink():
        raise ValidationError("Archive must contain exactly one regular application directory")
    app = apps[0].resolve(strict=True)
    if not app.is_relative_to(artifact):
        raise ValidationError("Archived application escapes the supplied archive")
    return artifact, app


def snapshot(app: Path) -> dict[str, Any]:
    """Fingerprint all bundle bytes; unsupported links fail instead of escaping."""
    digest = hashlib.sha256()
    count = total = 0
    for root, directories, files in os.walk(app, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories:
            if (Path(root) / name).is_symlink():
                raise ValidationError("Symbolic-link bundle layout requires separate manual review")
        for name in files:
            path = Path(root) / name
            if path.is_symlink() or not path.is_file():
                raise ValidationError("Nonregular bundle entry requires separate manual review")
            size = path.stat().st_size
            count += 1
            total += size
            if count > MAX_FILES or size > MAX_FILE_BYTES or total > MAX_BUNDLE_BYTES:
                raise ValidationError("Bundle exceeds bounded inspection limits")
            rel = path.relative_to(app).as_posix().encode("utf-8")
            content_hash = hashlib.sha256()
            actual = 0
            with path.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    actual += len(chunk)
                    if actual > MAX_FILE_BYTES:
                        raise ValidationError("Bundle file grew beyond inspection limit")
                    content_hash.update(chunk)
            if actual != size:
                raise ValidationError("Bundle file changed size during inspection")
            digest.update(len(rel).to_bytes(4, "big") + rel)
            digest.update(size.to_bytes(8, "big") + content_hash.digest())
    return {"sha256": digest.hexdigest(), "file_count": count, "total_bytes": total}


def png_dimensions(path: Path) -> tuple[int, int]:
    """Validate a complete bounded 8-bit RGB/RGBA PNG, including Apple CgBI."""
    data = read_bytes(path, 16 * 1024 * 1024)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValidationError(f"Not a PNG: {path.name}")
    cursor = 8
    header = None
    compressed = bytearray()
    cgbi = False
    ended = False
    idat_closed = False
    while cursor + 12 <= len(data):
        length = struct.unpack(">I", data[cursor:cursor + 4])[0]
        kind = data[cursor + 4:cursor + 8]
        end = cursor + 12 + length
        if end > len(data):
            raise ValidationError(f"Truncated PNG chunk: {path.name}")
        payload = data[cursor + 8:cursor + 8 + length]
        crc = struct.unpack(">I", data[cursor + 8 + length:end])[0]
        if zlib.crc32(kind + payload) != crc:
            raise ValidationError(f"PNG chunk CRC mismatch: {path.name}")
        if kind == b"CgBI":
            if cursor != 8 or cgbi or header is not None:
                raise ValidationError(f"Malformed CgBI ordering: {path.name}")
            cgbi = True
        if kind == b"IHDR":
            if length != 13 or header is not None or compressed:
                raise ValidationError(f"Invalid PNG IHDR: {path.name}")
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if not (0 < width <= 4096 and 0 < height <= 4096) or depth != 8 or color not in (2, 6) or compression != 0 or filtering != 0 or interlace != 0:
                raise ValidationError(f"PNG format exceeds supported 8-bit noninterlaced RGB/RGBA scope: {path.name}")
            header = (width, height, 3 if color == 2 else 4)
        elif kind == b"IDAT":
            if header is None or idat_closed:
                raise ValidationError(f"Malformed PNG IDAT ordering: {path.name}")
            compressed.extend(payload)
        elif kind == b"IEND":
            if length != 0 or not compressed or header is None or end != len(data):
                raise ValidationError(f"Malformed PNG end: {path.name}")
            ended = True
            break
        elif compressed:
            idat_closed = True
        elif header is None and kind != b"CgBI":
            raise ValidationError(f"PNG data precedes its IHDR: {path.name}")
        if kind not in (b"CgBI", b"IHDR", b"IDAT", b"IEND", b"PLTE") and kind[0] & 0x20 == 0:
            raise ValidationError(f"Unsupported critical PNG chunk: {path.name}")
        cursor = end
    if not ended or header is None:
        raise ValidationError(f"PNG is incomplete: {path.name}")
    width, height, channels = header
    row_bytes = width * channels + 1
    expected_size = row_bytes * height
    decoder = zlib.decompressobj(-15 if cgbi else zlib.MAX_WBITS)
    try:
        decoded = decoder.decompress(compressed, expected_size + 1)
    except zlib.error as error:
        raise ValidationError(f"PNG pixel stream does not decode: {path.name}") from error
    if len(decoded) != expected_size or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValidationError(f"PNG pixel stream size/end mismatch: {path.name}")
    if any(decoded[index] > 4 for index in range(0, expected_size, row_bytes)):
        raise ValidationError(f"PNG has an invalid scanline filter: {path.name}")
    return width, height


def macho_slices(path: Path, *, executable: bool) -> list[dict[str, Any]]:
    """Inspect bounded Mach-O headers; only ARM64 physical-iOS slices supported."""
    data = read_bytes(path, MAX_FILE_BYTES)
    slices: list[tuple[int, int]] = [(0, len(data))]
    fat_layouts = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
                   b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if data[:4] in fat_layouts:
        endian, fat64 = fat_layouts[data[:4]]
        if len(data) < 8:
            raise ValidationError("Truncated universal Mach-O header")
        count = struct.unpack_from(endian + "I", data, 4)[0]
        entry_size = 32 if fat64 else 20
        if not 0 < count <= 16 or 8 + count * entry_size > len(data):
            raise ValidationError("Malformed universal Mach-O slice inventory")
        slices = []
        for index in range(count):
            start = 8 + index * entry_size
            cpu = struct.unpack_from(endian + "I", data, start)[0]
            offset, size = struct.unpack_from(endian + ("QQ" if fat64 else "II"), data, start + 8)
            if cpu != 0x0100000C or size < 32 or offset < 8 + count * entry_size or offset + size > len(data):
                raise ValidationError("Unsupported or invalid universal Mach-O slice")
            slices.append((offset, size))
        ordered = sorted(slices)
        if any(a + size > b for (a, size), (b, _) in zip(ordered, ordered[1:])):
            raise ValidationError("Overlapping universal Mach-O slices")
    results = []
    for start, size in slices:
        magic = data[start:start + 4]
        endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">" if magic == b"\xfe\xed\xfa\xcf" else None
        if endian is None or size < 32:
            raise ValidationError(f"Payload is not supported 64-bit Mach-O: {path.name}")
        cpu, _, filetype, count, commands_size, _, _ = struct.unpack_from(endian + "7I", data, start + 4)
        if cpu != 0x0100000C or filetype != (2 if executable else 6):
            raise ValidationError(f"Payload architecture/type is not ARM64 iOS {'executable' if executable else 'library'}: {path.name}")
        if not 0 < count <= 20000 or commands_size > size - 32:
            raise ValidationError(f"Malformed Mach-O load-command table: {path.name}")
        cursor, end = start + 32, start + 32 + commands_size
        version = None
        for _ in range(count):
            if cursor + 8 > end:
                raise ValidationError(f"Truncated Mach-O load command: {path.name}")
            kind, command_size = struct.unpack_from(endian + "II", data, cursor)
            if command_size < 8 or command_size % 4 or cursor + command_size > end:
                raise ValidationError(f"Invalid Mach-O load-command length: {path.name}")
            if kind == 0x32:  # LC_BUILD_VERSION
                if command_size < 24 or version is not None:
                    raise ValidationError(f"Ambiguous Mach-O build version: {path.name}")
                target, minimum, sdk, tools = struct.unpack_from(endian + "4I", data, cursor + 8)
                if target != 2 or command_size != 24 + tools * 8:  # PLATFORM_IOS; excludes iOS simulator and Mac Catalyst.
                    raise ValidationError(f"Mach-O platform is not physical iOS: {path.name}")
                version = (minimum, sdk)
            elif kind == 0x25:  # Legacy LC_VERSION_MIN_IPHONEOS; ARM64 only above.
                if command_size != 16 or version is not None:
                    raise ValidationError(f"Ambiguous legacy iOS version: {path.name}")
                version = struct.unpack_from(endian + "II", data, cursor + 8)
            elif kind in (0x24, 0x2F, 0x30):
                raise ValidationError(f"Mach-O contains a non-iOS deployment command: {path.name}")
            cursor += command_size
        if cursor != end or version is None or not all(version):
            raise ValidationError(f"Mach-O lacks unambiguous iOS deployment/SDK metadata: {path.name}")
        decode = lambda packed: (packed >> 16, (packed >> 8) & 255, packed & 255)
        results.append({"architecture": "arm64", "platform": "iOS", "minimum_os": decode(version[0]), "sdk": decode(version[1])})
    return results


def marker_present(path: Path) -> bool:
    overlap = max(map(len, QA_MARKERS)) - 1
    tail = b""
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            data = tail + chunk
            if any(marker in data for marker in QA_MARKERS):
                return True
            tail = data[-overlap:]
    return False


def privacy_structure(value: dict[str, Any]) -> None:
    if "NSPrivacyTracking" in value and type(value["NSPrivacyTracking"]) is not bool:
        raise ValidationError("NSPrivacyTracking is not Boolean")
    domains = value.get("NSPrivacyTrackingDomains", [])
    if not isinstance(domains, list) or not all(isinstance(x, str) and x for x in domains):
        raise ValidationError("Malformed privacy tracking domains")
    for key, name_key, list_key in [
        ("NSPrivacyAccessedAPITypes", "NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"),
        ("NSPrivacyCollectedDataTypes", "NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypePurposes"),
    ]:
        rows = value.get(key, [])
        if not isinstance(rows, list):
            raise ValidationError(f"{key} is not an array")
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get(name_key), str) or not row[name_key]:
                raise ValidationError(f"Malformed {key} entry")
            items = row.get(list_key)
            if not isinstance(items, list) or not items or not all(isinstance(x, str) and x for x in items):
                raise ValidationError(f"Malformed {list_key}")
            if key == "NSPrivacyCollectedDataTypes":
                for flag in ["NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking"]:
                    if type(row.get(flag)) is not bool:
                        raise ValidationError(f"Malformed {flag}")


def command(argv: list[str]) -> subprocess.CompletedProcess[bytes]:
    # Fixed absolute programs and argument arrays; no shell, credentials or writes
    # to the artifact. codesign certificate extraction writes only public DER to
    # the short-lived private temporary directory allocated below.
    return subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=45, check=False)


def command_plist(result: subprocess.CompletedProcess[bytes]) -> dict[str, Any]:
    if result.returncode:
        raise ValidationError("Native metadata command failed")
    for raw in (result.stdout, result.stderr):
        if not raw:
            continue
        candidates = [raw]
        start, end = raw.find(b"<?xml"), raw.rfind(b"</plist>")
        if start >= 0 and end >= start:
            candidates.append(raw[start:end + len(b"</plist>")])
        for candidate in candidates:
            try:
                return plist_dict(candidate)
            except ValidationError:
                pass
    raise ValidationError("Native command did not provide a dictionary property list")


def native_evidence(app: Path, expected: dict[str, str]) -> dict[str, Any]:
    """Collect actual macOS evidence, never fall back to unsigned or ad hoc."""
    requirement = ('=anchor apple generic and identifier "' + expected["bundle_id"]
                   + '" and certificate leaf[subject.OU] = "' + expected["team_id"] + '"')
    verified = command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", "-R", requirement, str(app)])
    if verified.returncode:
        raise ValidationError(f"codesign verification with expected Apple team/identifier failed (exit {verified.returncode})")
    entitlements = command_plist(command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)]))
    profile_path = app / "embedded.mobileprovision"
    read_bytes(profile_path)
    profile = command_plist(command(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)]))
    with tempfile.TemporaryDirectory(prefix="app-store-artifact-certificate-") as temporary:
        prefix = str(Path(temporary) / "signer-")
        extraction = command(["/usr/bin/codesign", "-d", "--extract-certificates=" + prefix, str(app)])
        if extraction.returncode:
            raise ValidationError("Could not extract the public signing certificate")
        certificate = read_bytes(Path(prefix + "0"), 1024 * 1024)
    return {"entitlements": entitlements, "profile": profile, "certificate": certificate}


def profile_allows(allowed: Any, claimed: Any) -> bool:
    if isinstance(claimed, str) and isinstance(allowed, str):
        if allowed == claimed:
            return True
        return allowed.endswith("*") and "*" not in allowed[:-1] and claimed.startswith(allowed[:-1])
    if isinstance(claimed, list) and isinstance(allowed, list):
        return all(any(profile_allows(a, c) for a in allowed) for c in claimed)
    if isinstance(claimed, dict) and isinstance(allowed, dict):
        return all(k in allowed and profile_allows(allowed[k], v) for k, v in claimed.items())
    return type(claimed) is type(allowed) and claimed == allowed


def validate_signing(evidence: dict[str, Any], expected: dict[str, str], now: dt.datetime, lumina: bool) -> dict[str, Any]:
    ent = evidence["entitlements"]
    profile = evidence["profile"]
    if not isinstance(ent, dict) or not isinstance(profile, dict):
        raise ValidationError("Missing actual entitlements or decoded profile")
    grant = profile.get("Entitlements")
    if not isinstance(grant, dict):
        raise ValidationError("Provisioning profile has no entitlement dictionary")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime):
        raise ValidationError("Provisioning profile expiration is unavailable")
    expiry = expiry.replace(tzinfo=UTC) if expiry.tzinfo is None else expiry.astimezone(UTC)
    if expiry <= now:
        raise ValidationError("Provisioning profile is expired")
    created = profile.get("CreationDate")
    if isinstance(created, dt.datetime):
        created = created.replace(tzinfo=UTC) if created.tzinfo is None else created.astimezone(UTC)
        if created > now:
            raise ValidationError("Provisioning profile creation is in the future")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices") not in (None, False):
        raise ValidationError("Profile is device-limited or enterprise, not an App Store distribution profile")
    if ent.get("get-task-allow") is not False or grant.get("get-task-allow") is not False:
        raise ValidationError("Signed app and profile must both disable get-task-allow")
    if grant.get("beta-reports-active") is not True or ent.get("beta-reports-active") is not True:
        raise ValidationError("Current App Store profile markers are missing; profile format needs review")
    platforms = profile.get("Platform")
    if not isinstance(platforms, list) or not all(isinstance(x, str) for x in platforms) or "iOS" not in platforms:
        raise ValidationError("Profile does not authorize iOS")
    teams = profile.get("TeamIdentifier")
    if not isinstance(teams, list) or not all(isinstance(x, str) for x in teams) or expected["team_id"] not in teams:
        raise ValidationError("Provisioning team does not match expected team")
    for values in (ent, grant):
        if values.get("com.apple.developer.team-identifier") != expected["team_id"]:
            raise ValidationError("Signed/profile team entitlement mismatch")
    app_identifier = ent.get("application-identifier")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if not isinstance(prefixes, list) or not any(app_identifier == prefix + "." + expected["bundle_id"] for prefix in prefixes if isinstance(prefix, str)):
        raise ValidationError("Signed application identifier does not match the expected app and authorized prefix")
    # Legacy App ID prefixes can differ from the Team ID; do not conflate them.
    for key, value in ent.items():
        if key not in grant or not profile_allows(grant[key], value):
            raise ValidationError(f"Signed entitlement is not authorized by the profile: {key}")
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or not evidence.get("certificate") or evidence["certificate"] not in certificates:
        raise ValidationError("Actual signing certificate is not authorized by the profile")
    if lumina:
        if ent.get("com.apple.security.application-groups") != ["group.SA.Lumina"]:
            raise ValidationError("Lumina signed app group differs from the preserved storage group")
        for key in ent:
            if (key.startswith(("com.apple.developer.icloud", "com.apple.developer.ubiquity"))
                    or key in {"aps-environment", "com.apple.developer.aps-environment"}):
                raise ValidationError("Offline Lumina contains an unused cloud or APNs entitlement")
    return {"team_id": expected["team_id"], "application_identifier": app_identifier,
            "profile_expiration_utc": expiry.isoformat(),
            "signer_certificate_sha256": hashlib.sha256(evidence["certificate"]).hexdigest()}


def validate_artifact(path: Path, expected: dict[str, str], *, lumina: bool = False,
                      system_name: str | None = None,
                      provider: Callable[[Path, dict[str, str]], dict[str, Any]] = native_evidence,
                      now: dt.datetime | None = None) -> dict[str, Any]:
    now = now or dt.datetime.now(UTC)
    report: dict[str, Any] = {
        "schema_version": 1, "checked_at_utc": now.isoformat(), "artifact": str(path),
        "result": "BLOCKED", "submission_ready": False, "app_store_acceptance": "NOT_CHECKED",
        "scope": "Read-only local signed-artifact inspection; not native QA or permission to submit",
        "expected": expected.copy(), "checks": [],
        "external_gates": [
            "Exact candidate source provenance and current unit/UI/physical-device acceptance",
            "Privacy semantics, SDK behavior/consent, policy and support hosting, accessibility and store metadata",
            "Current Apple SDK/submission policy, account/agreements and Xcode/App Store validation",
            "Profile DER authorization and nested-target behavior remain subject to native platform/Apple validation",
        ],
    }
    checks = report["checks"]

    def check(name: str, action: Callable[[], Any]) -> Any:
        try:
            result = action()
            checks.append({"name": name, "status": "PASS"})
            return result
        except (ValidationError, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError) as error:
            checks.append({"name": name, "status": "FAIL", "detail": str(error)})
            return None

    def require(condition: bool, detail: str) -> None:
        if not condition:
            raise ValidationError(detail)

    resolved = check("artifact_layout", lambda: artifact_app(path))
    if resolved is None:
        return report
    artifact, app = resolved
    report.update({"artifact": str(artifact), "app": str(app)})
    before = check("initial_bundle_fingerprint", lambda: snapshot(app))
    info = check("info_plist", lambda: plist_dict(read_bytes(app / "Info.plist")))
    if info is not None:
        metadata = {key: info.get(key) for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "DTXcode", "DTXcodeBuild", "DTSDKName", "DTSDKBuild", "MinimumOSVersion", "UIDeviceFamily", "CFBundleSupportedPlatforms"]}
        report["metadata"] = metadata

        def identity() -> None:
            for key, wanted in [("CFBundleIdentifier", expected["bundle_id"]), ("CFBundleShortVersionString", expected["version"]), ("CFBundleVersion", expected["build"])]:
                require(isinstance(info.get(key), str) and info[key] == wanted, f"{key} differs from the explicit expected value")
            require(info.get("CFBundlePackageType") == "APPL", "Payload is not an application")
            platforms = info.get("CFBundleSupportedPlatforms")
            require(isinstance(platforms, list) and "iPhoneOS" in platforms, "Payload is not a physical iOS application")
            require(bool(re.fullmatch(r"iphoneos\d+(?:\.\d+)*", str(info.get("DTSDKName", "")))), "Physical iOS SDK metadata is missing or malformed")
            require(bool(re.fullmatch(r"\d+(?:\.\d+)*", str(info.get("MinimumOSVersion", "")))), "MinimumOSVersion is missing or malformed")
            require(bool(str(info.get("DTXcode", ""))) and bool(str(info.get("DTSDKBuild", ""))), "Xcode/SDK build provenance is missing")
            require(not lumina or expected["bundle_id"] == "SA.Lumina", "Lumina policy requires the known SA.Lumina identity")

        check("identity_version_and_sdk", identity)

        def executable_check() -> None:
            name = info.get("CFBundleExecutable")
            require(isinstance(name, str) and name not in ("", ".", "..") and Path(name).name == name and "/" not in name, "Executable name is unsafe or missing")
            executable = app / name
            require(executable.is_file() and not executable.is_symlink() and executable.stat().st_size > 0, "Executable is missing or not a regular nonempty file")
            require(not marker_present(executable), "Production executable contains a known Lumina QA launch marker")

        check("executable_and_qa_markers", executable_check)

        def payload_platform_check() -> None:
            name = info.get("CFBundleExecutable")
            require(isinstance(name, str) and name not in ("", ".", "..") and Path(name).name == name and "/" not in name, "Executable name is unsafe or missing")
            def version_tuple(value: str) -> tuple[int, int, int]:
                require(isinstance(value, str) and bool(re.fullmatch(r"\d+(?:\.\d+){0,2}", value)), "Unsupported deployment/SDK version format")
                return tuple((list(map(int, value.split("."))) + [0, 0])[:3])
            minimum = version_tuple(info.get("MinimumOSVersion"))
            sdk_name = info.get("DTSDKName")
            require(isinstance(sdk_name, str) and sdk_name.startswith("iphoneos"), "Physical iOS SDK metadata is unavailable")
            sdk = version_tuple(sdk_name[len("iphoneos"):])
            main_slices = macho_slices(app / name, executable=True)
            require(all(row["minimum_os"] == minimum and row["sdk"] == sdk for row in main_slices), "Main Mach-O deployment/SDK metadata differs from Info.plist")
            libraries = set(app.rglob("*.dylib"))
            for framework in app.rglob("*.framework"):
                framework_info = plist_dict(read_bytes(framework / "Info.plist"))
                library_name = framework_info.get("CFBundleExecutable")
                require(isinstance(library_name, str) and library_name not in ("", ".", "..") and Path(library_name).name == library_name and "/" not in library_name, "Framework executable name is unsafe or missing")
                libraries.add(framework / library_name)
            require(len(libraries) <= 500, "Nested library inventory exceeds inspection bounds")
            for library in sorted(libraries):
                rows = macho_slices(library, executable=False)
                require(all(row["minimum_os"] <= minimum for row in rows), f"Nested library requires an OS above the app minimum: {library.name}")
            report["payload_platforms"] = {"main_slices": main_slices, "nested_libraries_checked": len(libraries)}

        check("mach_o_platform_and_deployment", payload_platform_check)

        def icon_check() -> None:
            require((app / "Assets.car").is_file() and (app / "Assets.car").stat().st_size > 0, "Compiled asset catalogue is missing or empty")
            families = info.get("UIDeviceFamily")
            require(isinstance(families, list) and all(type(n) is int for n in families) and 1 in families, "iPhone device-family declaration is missing")
            for key, dimension in [("CFBundleIcons", (120, 120))] + ([("CFBundleIcons~ipad", (152, 152))] if 2 in families else []):
                icon_group = info.get(key)
                require(isinstance(icon_group, dict), f"{key} is missing or malformed")
                primary = icon_group.get("CFBundlePrimaryIcon", {})
                require(isinstance(primary, dict) and isinstance(primary.get("CFBundleIconName"), str) and bool(primary["CFBundleIconName"]), f"{key} primary icon name is missing")
                if lumina:
                    require(primary["CFBundleIconName"] == "AppIcon", f"{key} does not select Lumina's AppIcon")
                    names = primary.get("CFBundleIconFiles")
                    require(isinstance(names, list) and names and all(isinstance(n, str) and n and Path(n).name == n for n in names), f"{key} icon file declarations are missing or unsafe")
                    matches = [p for p in app.glob("*.png") if any(p.stem.split("@")[0].split("~")[0] == Path(n).stem.split("@")[0].split("~")[0] for n in names)]
                    require(any(png_dimensions(p) == dimension for p in matches), f"{key} lacks a matching compiled {dimension[0]}x{dimension[1]} icon")

        check("compiled_icon_metadata_and_payload", icon_check)

    def privacy_check() -> None:
        root = app / "PrivacyInfo.xcprivacy"
        require(root.is_file(), "Root privacy manifest is absent; this validator requires explicit privacy evidence")
        manifests = sorted(app.rglob("PrivacyInfo.xcprivacy"))
        for manifest in manifests:
            value = plist_dict(read_bytes(manifest))
            privacy_structure(value)
            if lumina and manifest == root:
                require(value.get("NSPrivacyTracking") is False, "Lumina's current offline policy requires NSPrivacyTracking=false")
                reasons = {reason for row in value.get("NSPrivacyAccessedAPITypes", []) if row.get("NSPrivacyAccessedAPIType") == "NSPrivacyAccessedAPICategoryUserDefaults" for reason in row["NSPrivacyAccessedAPITypeReasons"]}
                require({"CA92.1", "1C8F.1"}.issubset(reasons), "Lumina's reviewed UserDefaults declarations are missing")
                # Recovery uses local deadlines and user-selected file metadata.
                for category, required in {
                    "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"},
                    "NSPrivacyAccessedAPICategoryFileTimestamp": {"3B52.1"},
                }.items():
                    declared = {reason for row in value.get("NSPrivacyAccessedAPITypes", [])
                                if row.get("NSPrivacyAccessedAPIType") == category
                                for reason in row["NSPrivacyAccessedAPITypeReasons"]}
                    require(required.issubset(declared),
                            f"Lumina's reviewed recovery privacy declarations are missing: {category}")
        report["privacy_manifest_count"] = len(manifests)

    check("packaged_privacy_manifests", privacy_check)
    check("supported_target_scope", lambda: require(not any(app.rglob("*.appex")) and not any(app.rglob("*.app")), "Embedded app/extension targets require separate per-target validation; unsupported here"))
    check("embedded_distribution_material", lambda: require((app / "_CodeSignature" / "CodeResources").is_file() and (app / "embedded.mobileprovision").is_file(), "Code signature resources or embedded provisioning profile are missing"))
    actual_system = system_name or platform.system()
    if actual_system != "Darwin":
        checks.append({"name": "native_distribution_signature_and_profile", "status": "NOT_RUN", "detail": "Actual macOS codesign/security evidence is required; this platform cannot pass the gate"})
    else:
        signing = check("native_distribution_signature_and_profile", lambda: validate_signing(provider(app, expected), expected, now, lumina))
        if signing is not None:
            report["signing"] = signing
    after = check("final_bundle_fingerprint", lambda: snapshot(app))
    check("artifact_stable_during_inspection", lambda: require(before is not None and after == before, "Bundle changed during inspection or its fingerprint could not be established"))
    if before is not None:
        report["bundle_fingerprint"] = before
    if checks and all(item["status"] == "PASS" for item in checks):
        report["result"] = "ARTIFACT_CHECKS_PASSED"
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--lumina", action="store_true", help="Also validate reviewed Lumina icon/iCloud/privacy/QA packaging")
    parser.add_argument("--output", type=Path, help="Optional NEW report path outside the input artifact")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", args.bundle_id) or not re.fullmatch(r"[A-Za-z0-9]+", args.team_id):
        parser.error("Bundle/team IDs contain unsupported characters")
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", args.version) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", args.build):
        parser.error("Expected version/build must be explicit numeric release identifiers")
    if args.output:
        output = args.output.expanduser().resolve()
        artifact = args.artifact.expanduser().resolve()
        if output.is_relative_to(artifact) or output.exists():
            parser.error("Report must be a new file outside the supplied artifact")
    expected = {"bundle_id": args.bundle_id, "version": args.version, "build": args.build, "team_id": args.team_id}
    report = validate_artifact(args.artifact, expected, lumina=args.lumina)
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        with output.open("x", encoding="utf-8") as handle:
            handle.write(encoded)
    print(encoded, end="")
    return 0 if report["result"] == "ARTIFACT_CHECKS_PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
