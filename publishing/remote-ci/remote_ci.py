#!/usr/bin/env python3
"""File review and isolated GitHub-hosted Lumina verification.

`inspect` is file-only. prepare/run/collect require the reviewed GitHub context.
The distinct remote-v6 runner is pinned; no local Mac coordinator is imported.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
from typing import Any

RUNNER_SHA = "1272c31a0e07992b81adc594b0407ed5c519c09f7140824317e7b0185d210413"
COUNTS = {"LuminaTests": 69, "LuminaUITests": 21}
MAX_ARTIFACT_BYTES = 500_000_000
DERIVED_LANES = frozenset({"lumina-uiqa", "lumina-production", "lumina-ci-settings-release", "lumina-ci-settings-uiqa"})
REPRODUCIBLE_CACHES = frozenset({"Build", "SDKExplicitPrecompiledModules", "ModuleCache.noindex",
                               "SDKStatCaches.noindex", "CompilationCache.noindex"})
PLAN_FILES = {
    "source_files_sha256": "expected-source-files.json",
    "native_paths_sha256": "native-source-paths.json",
    "inventory_policy_sha256": "inventory-policy.json",
    "test_selection_sha256": "test-selection.json",
    "runner_sha256": "Runner/verify_publishing.py",
}


class GateFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GateFailure(message)


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path: Path) -> Any:
    require(path.is_file() and not path.is_symlink(), "Missing or linked JSON input: " + str(path))
    return json.loads(path.read_bytes(), object_pairs_hook=unique_object)


def write_json(path: Path, value: Any) -> str:
    data = (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)
    os.chmod(path, 0o600)
    return sha_bytes(data)


def relative_path(value: str) -> PurePosixPath:
    require(isinstance(value, str) and bool(value), "Empty relative path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and str(path) == value and ".." not in path.parts
            and ".git" not in path.parts and "\\" not in value
            and not any(ord(c) < 32 for c in value), "Unsafe relative path: " + repr(value))
    return path


def git_blob(data: bytes) -> str:
    return hashlib.sha1(("blob " + str(len(data)) + "\0").encode() + data).hexdigest()


def expected_mode(record: dict[str, Any]) -> int:
    require(record.get("git_mode") in {"100644", "100755"}, "Unsupported Git mode")
    return 0o755 if record["git_mode"] == "100755" else 0o644


def validate_files(root: Path, expected: dict[str, Any], *, complete: bool = True) -> None:
    require(root.is_dir() and not root.is_symlink(), "Missing/linked source directory")
    if complete:
        found = {str(p.relative_to(root)) for p in root.rglob("*")
                 if ".git" not in p.relative_to(root).parts and (p.is_file() or p.is_symlink())}
        require(found == set(expected), "Source inventory gained or lost a member")
    for name, record in expected.items():
        relative_path(name)
        path = root / name
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and not path.is_symlink(), "Source member is not regular: " + name)
        require(stat.S_IMODE(info.st_mode) == expected_mode(record), "Source mode changed: " + name)
        require(info.st_size == record["bytes"] and sha_file(path) == record["sha256"],
                "Source bytes changed: " + name)


def validate_selection(selection: dict[str, Any]) -> None:
    require(selection.get("source_plan_counts") == COUNTS, "Full 69+21 source plan required")
    mode = selection.get("full_mode", {})
    require(mode == {"counts": COUNTS, "execution_filters": [], "expected_total": 90,
                     "scope": "FULL_90_CASE_TEST_GATE"}, "Full unfiltered execution required")
    require(selection.get("focused_execution_allowed") is False, "Focused execution prohibited")
    methods = selection.get("source_methods", {})
    require(set(methods) == set(COUNTS), "Unexpected test target")
    for target, count in COUNTS.items():
        values = methods[target]
        require(isinstance(values, list) and len(values) == count and len(set(values)) == count,
                "Missing or duplicate test method: " + target)


def load_plan(control: Path) -> dict[str, Any]:
    directory = control / "publishing/remote-ci"
    config = read_json(directory / "candidate.json")
    require(config.get("schema_version") == 1 and config.get("repository") == "swonyu/Lumina", "Wrong plan")
    for key, name in PLAN_FILES.items():
        require(sha_file(directory / name) == config.get(key), "Unreviewed plan member: " + name)
    require(config["runner_sha256"] == RUNNER_SHA, "Reviewed remote-v6 runner required")
    source = read_json(directory / "expected-source-files.json")
    files = source.get("files", {})
    require(source.get("expected_file_count") == 190 and len(files) == 190, "Complete 190-file source required")
    for name, record in files.items():
        relative_path(name)
        expected_mode(record)
        require(type(record.get("bytes")) is int and record["bytes"] >= 0
                and re.fullmatch(r"[a-f0-9]{64}", record.get("sha256", "")) is not None
                and re.fullmatch(r"[a-f0-9]{40}", record.get("git_blob", "")) is not None,
                "Malformed source binding: " + name)
    native = read_json(directory / "native-source-paths.json")
    require(isinstance(native, list) and len(native) == 120 and len(set(native)) == 120
            and set(native).issubset(files), "Exact 120 native source members required")
    selection = read_json(directory / "test-selection.json")
    validate_selection(selection)
    require(source.get("source_commit") == config.get("candidate_commit")
            and selection.get("source_commit") == config.get("candidate_commit"), "Source version metadata disagrees")
    require(config.get("native_deadline_minutes") == 45 and config.get("artifact_retention_days") == 1,
            "Reviewed deadline/retention changed")
    require(config.get("developer_dir") == "/Applications/Xcode_26.5.app/Contents/Developer"
            and config.get("xcode_build") == "17F42"
            and config.get("sim_runtime_id") == "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
            and config.get("sim_device_name") == "iPhone 17 Pro", "Unreviewed SDK/device change")
    return {"directory": directory, "config": config, "files": files, "native": native,
            "selection": selection, "policy": read_json(directory / "inventory-policy.json"),
            "plan_sha": sha_file(directory / "candidate.json")}


def validate_authority(config: dict[str, Any], cost: dict[str, Any], now: dt.datetime) -> None:
    for key in ("candidate_commit", "candidate_tree"):
        require(isinstance(config.get(key), str) and re.fullmatch(r"[a-f0-9]{40}", config[key]) is not None,
                "Candidate source is UNBOUND: " + key)
    require(config.get("native_authorization") == "ROOT_REVIEWED_GITHUB_VM_ONLY", "Native authorization is UNBOUND")
    require(re.fullmatch(r"[a-f0-9]{64}", config.get("native_review_receipt_sha256") or "") is not None,
            "Native review receipt is UNBOUND")
    require(cost.get("schema_version") == 1 and cost.get("status") == "ZERO_EXTRA_SPEND_VERIFIED"
            and cost.get("repository") == config["repository"]
            and cost.get("public_standard_runner_only") is True
            and cost.get("extra_spending_permitted") is False
            and cost.get("usage_blocked_at_zero_budget") is True
            and cost.get("caches_allowed") is False and cost.get("retention_days") == 1
            and cost.get("maximum_artifact_bytes") == MAX_ARTIFACT_BYTES
            and re.fullmatch(r"[a-f0-9]{64}", cost.get("private_verification_receipt_sha256") or "") is not None,
            "Free evidence delivery policy is UNBOUND or changed")
    deadline = dt.datetime.fromisoformat(config["deadline_utc"].replace("Z", "+00:00"))
    require(deadline.tzinfo is not None and (deadline - now).total_seconds() >= 3600,
            "The original user deadline has insufficient time for this job")


def hosted_context(config: dict[str, Any], control: Path) -> dict[str, str]:
    env = os.environ
    require(sys.platform == "darwin" and platform.machine() == "arm64", "Requires hosted ARM64 macOS")
    require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_OS") == "macOS"
            and env.get("RUNNER_ARCH") == "ARM64" and env.get("LUMINA_RUNNER_ENVIRONMENT") == "github-hosted",
            "Requires a fresh standard GitHub-hosted VM")
    require(env.get("GITHUB_REPOSITORY") == config["repository"] and env.get("GITHUB_EVENT_NAME") == "push"
            and env.get("GITHUB_REF") == "refs/heads/" + config["workflow_branch"], "Wrong repository/event/branch")
    event = read_json(Path(env["GITHUB_EVENT_PATH"]))
    require(event.get("repository", {}).get("private") is False
            and event["repository"].get("full_name") == config["repository"], "Public repository evidence required")
    require(config.get("runner_label") == "macos-26" and platform.mac_ver()[0].split(".")[0] == "26"
            and bool(env.get("ImageOS")) and bool(env.get("ImageVersion")), "Wrong/unidentified runner image")
    workspace = Path(env["GITHUB_WORKSPACE"]).resolve()
    require(control == workspace / "control" and control.is_dir(), "Control checkout must be in this VM workspace")
    require(re.fullmatch(r"[a-f0-9]{40}", env.get("GITHUB_SHA", "")) is not None, "Missing workflow commit")
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[0-9]+", env.get(key, "")) is not None, "Missing job identity")
    require(env["GITHUB_RUN_ATTEMPT"] == "1", "Automatic/manual reruns require a separately reviewed new job")
    require(Path(env["RUNNER_TEMP"]).is_dir(), "Missing VM temporary directory")
    context = {key: env.get(key, "") for key in ("GITHUB_REPOSITORY", "GITHUB_SHA", "GITHUB_REF", "GITHUB_RUN_ID",
               "GITHUB_RUN_ATTEMPT", "RUNNER_OS", "RUNNER_ARCH", "LUMINA_RUNNER_ENVIRONMENT", "ImageOS", "ImageVersion")}
    context["actual_macos_version"] = platform.mac_ver()[0]
    return context


def locations(context: dict[str, str]) -> dict[str, Path]:
    suffix = context["GITHUB_RUN_ID"] + "-" + context["GITHUB_RUN_ATTEMPT"]
    temporary = Path(os.environ["RUNNER_TEMP"]).resolve()
    root = temporary / ("lumina-native-" + suffix)
    return {"root": root, "candidate": root / "Candidate", "stage": root / "Stage",
            "output": root / "NativeRuns", "evidence": temporary / ("lumina-evidence-" + suffix)}


def command(args: list[str], cwd: Path, *, log: Path | None = None, timeout: int = 60) -> str:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False)
    if log is not None:
        write_json(log, {"argv": args, "exit_code": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    require(result.returncode == 0, "Command failed: " + args[0] + " (" + str(result.returncode) + ")")
    return result.stdout


def load_cost(plan: dict[str, Any]) -> dict[str, Any]:
    config = plan["config"]
    name = config.get("evidence_cost_receipt")
    require(name == "evidence-cost-policy.json", "Evidence cost policy is UNBOUND")
    path = plan["directory"] / name
    require(sha_file(path) == config.get("evidence_cost_receipt_sha256"), "Evidence cost policy changed")
    return read_json(path)


def stage_seal(root: Path) -> dict[str, Any]:
    files: dict[str, Any] = {}
    for path in sorted(root.rglob("*")):
        require(not path.is_symlink(), "Stage contains a symlink")
        if path.is_file():
            files[str(path.relative_to(root))] = {"sha256": sha_file(path), "bytes": path.stat().st_size,
                                                 "mode": stat.S_IMODE(path.stat().st_mode)}
    return {"schema_version": 1, "files": files}


def check_seal(root: Path, expected: dict[str, Any]) -> None:
    require(stage_seal(root) == expected, "Sealed package bytes, modes or membership changed")


def outputs(values: dict[str, str]) -> None:
    path = Path(os.environ["GITHUB_OUTPUT"])
    with path.open("a") as stream:
        for key, value in values.items():
            require("\n" not in value and "\r" not in value, "Invalid output value")
            stream.write(key + "=" + value + "\n")


def prepare(control: Path, plan: dict[str, Any]) -> None:
    config = plan["config"]
    context = hosted_context(config, control)
    validate_authority(config, load_cost(plan), dt.datetime.now(dt.timezone.utc))
    require(command(["git", "rev-parse", "HEAD"], control).strip() == context["GITHUB_SHA"], "Wrong workflow checkout")
    require(not command(["git", "status", "--porcelain"], control).strip(), "Workflow checkout is dirty")
    paths = locations(context)
    require(not paths["root"].exists() and not paths["evidence"].exists(), "Never reuse a prior job directory")
    paths["root"].mkdir(mode=0o700)
    write_json(paths["root"] / "host-context.json", context)
    write_json(paths["root"] / "reviewed-plan.json", config)
    write_json(paths["root"] / "reviewed-cost-policy.json", load_cost(plan))
    os.environ["DEVELOPER_DIR"] = config["developer_dir"]
    version = command(["xcodebuild", "-version"], paths["root"], log=paths["root"] / "xcode-version.json")
    require("Xcode 26.5\n" in version and "Build version 17F42" in version, "Xcode version mismatch")
    for sdk in ("iphoneos", "iphonesimulator"):
        value = command(["xcrun", "--sdk", sdk, "--show-sdk-version"], paths["root"], log=paths["root"] / (sdk + ".json"))
        require(value.strip() == "26.5", "Required SDK unavailable")
    runtimes = json.loads(command(["xcrun", "simctl", "list", "runtimes", "--json"], paths["root"], log=paths["root"] / "runtimes.json"))
    require(any(x.get("identifier") == config["sim_runtime_id"] and x.get("isAvailable") is True
                for x in runtimes.get("runtimes", [])), "Required simulator runtime unavailable")
    device_types = json.loads(command(["xcrun", "simctl", "list", "devicetypes", "--json"], paths["root"], log=paths["root"] / "device-types.json"))
    require(any(x.get("name") == config["sim_device_name"] for x in device_types.get("devicetypes", [])), "Required device type unavailable")
    write_json(paths["root"] / "disk-before.json", {"free_bytes": shutil.disk_usage(paths["root"]).free})
    require(shutil.disk_usage(paths["root"]).free >= 5 * 1024 ** 3, "Insufficient fresh VM disk")
    paths["candidate"].mkdir(mode=0o700)
    command(["git", "init", "--quiet"], paths["candidate"])
    command(["git", "remote", "add", "origin", "https://github.com/swonyu/Lumina.git"], paths["candidate"])
    command(["git", "fetch", "--depth=1", "origin", config["candidate_commit"]], paths["candidate"],
            log=paths["root"] / "source-fetch.json", timeout=180)
    command(["git", "checkout", "--detach", config["candidate_commit"]], paths["candidate"])
    require(command(["git", "rev-parse", "HEAD^{tree}"], paths["candidate"]).strip() == config["candidate_tree"], "Wrong source tree")
    entries = command(["git", "ls-tree", "-rz", "HEAD"], paths["candidate"])
    observed = {}
    for item in entries.split("\0"):
        if item:
            meta, name = item.split("\t", 1)
            mode, kind, oid = meta.split()
            require(kind == "blob", "Unexpected source object")
            observed[name] = (mode, oid)
    require(observed == {p: (v["git_mode"], v["git_blob"]) for p, v in plan["files"].items()}, "Git objects/modes differ from reviewed source")
    validate_files(paths["candidate"], plan["files"])
    source = paths["stage"] / "Source"
    source.mkdir(parents=True)
    for name in plan["native"]:
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(paths["candidate"] / name, target, follow_symlinks=False)
        os.chmod(target, expected_mode(plan["files"][name]))
    validate_files(source, {p: plan["files"][p] for p in plan["native"]})
    runner = paths["stage"] / "Runner/verify_publishing.py"
    runner.parent.mkdir()
    shutil.copy2(plan["directory"] / "Runner/verify_publishing.py", runner)
    os.chmod(runner, 0o644)
    selection = paths["stage"] / "Evidence/TEST-SELECTION.json"
    write_json(selection, plan["selection"])
    modes = paths["stage"] / "Evidence/SOURCE-GIT-MODES.json"
    write_json(modes, {p: plan["files"][p]["git_mode"] for p in plan["native"]})
    binding = paths["stage"] / "Evidence/SOURCE-BINDING.json"
    write_json(binding, {"commit": config["candidate_commit"], "tree": config["candidate_tree"],
                        "all_source_files": plan["files"], "native_paths": plan["native"]})
    manifest = {"schema_version": 2, "inventory_policy": plan["policy"],
                "roots": [{"key": "lumina", "path": str(source),
                           "files": {p: plan["files"][p]["sha256"] for p in plan["native"]}}],
                "additional_files": {str(p): sha_file(p) for p in (runner, selection, modes, binding)}}
    write_json(paths["stage"] / "Evidence/source-manifest.json", manifest)
    seal_sha = write_json(paths["root"] / "STAGE-SEAL.json", stage_seal(paths["stage"]))
    write_json(paths["root"] / "READY.json", {"plan_sha256": plan["plan_sha"], "stage_seal_sha256": seal_sha,
                                               "context": context, "candidate_commit": config["candidate_commit"]})
    outputs({"prepared": "true", "candidate_commit": config["candidate_commit"]})


def ready(control: Path, plan: dict[str, Any]) -> tuple[dict[str, str], dict[str, Path]]:
    context = hosted_context(plan["config"], control)
    paths = locations(context)
    record = read_json(paths["root"] / "READY.json")
    require(record.get("context") == context and record.get("plan_sha256") == plan["plan_sha"]
            and record.get("candidate_commit") == plan["config"]["candidate_commit"], "Stale or replaced preparation")
    require(sha_file(paths["root"] / "STAGE-SEAL.json") == record.get("stage_seal_sha256"), "Stage seal replaced")
    return context, paths


def run_native(control: Path, plan: dict[str, Any]) -> None:
    config = plan["config"]
    validate_authority(config, load_cost(plan), dt.datetime.now(dt.timezone.utc))
    context, paths = ready(control, plan)
    check_seal(paths["stage"], read_json(paths["root"] / "STAGE-SEAL.json"))
    require(not paths["output"].exists(), "Native output already exists; never retry/reuse")
    argv = [sys.executable, str(paths["stage"] / "Runner/verify_publishing.py"),
            "--apps", "lumina", "--slot-authorized", "github-" + context["GITHUB_RUN_ID"] + "-" + context["GITHUB_RUN_ATTEMPT"],
            "--deadline-minutes", "45", "--lumina-root", str(paths["stage"] / "Source"),
            "--halal-root", str(paths["root"] / "UnusedHalalRoot"),
            "--career-root", str(paths["root"] / "UnusedCareerRoot"),
            "--output-root", str(paths["output"]), "--source-manifest", str(paths["stage"] / "Evidence/source-manifest.json"),
            "--sim-runtime-id", config["sim_runtime_id"], "--sim-device-name", config["sim_device_name"]]
    write_json(paths["root"] / "NATIVE-INVOCATION.json", {"argv": argv, "runner_sha256": RUNNER_SHA,
                                                        "workflow_commit": context["GITHUB_SHA"],
                                                        "source_commit": config["candidate_commit"]})
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = config["developer_dir"]
    os.execve(sys.executable, argv, env)  # Preserve the reviewed runner's signal/cleanup ownership.


def native_passed(report: dict[str, Any], selection: dict[str, Any], step_outcome: str) -> bool:
    if not isinstance(report, dict):
        return False
    inventory = report.get("lumina_test_inventory", {})
    apps = report.get("app_results", {})
    if not isinstance(inventory, dict) or not isinstance(apps, dict):
        return False
    result = apps.get("lumina", {})
    steps = report.get("steps", [])
    if not isinstance(result, dict) or not isinstance(steps, list) or not all(isinstance(s, dict) for s in steps):
        return False
    return (step_outcome == "success" and type(report.get("exit_code")) is int and report["exit_code"] == 0
            and report.get("cleanup_safe") is True
            and report.get("errors") == [] and report.get("apps") == ["lumina"]
            and report.get("skip_production") is False and report.get("can_satisfy_full_lumina_test_gate") is True
            and report.get("lumina_test_scope") == "FULL_90_CASE_TEST_GATE"
            and result.get("status") == "passed" and result.get("source_hashes_unchanged") is True
            and result.get("production_included") is True and report.get("source_manifest_status") == "passed"
            and inventory.get("scope") == "FULL_90_CASE_TEST_GATE" and inventory.get("full_test_gate_passed") is True
            and inventory.get("test_counts") == COUNTS
            and inventory.get("passed_test_identifiers") == selection["source_methods"]
            and report.get("lumina_test_counts") == {"totalTestCount": 90, "passedTests": 90, "failedTests": 0,
                                                      "skippedTests": 0, "expectedFailures": 0}
            and any(step.get("name") == "lumina-release-archive-verifier" and step.get("status") == "passed"
                    for step in steps))


def candidate_git_metadata(relative: PurePosixPath) -> bool:
    return relative.parts[:2] == ("Candidate", ".git")


def reproducible_cache_member(relative: PurePosixPath) -> bool:
    parts = relative.parts
    if (len(parts) < 6 or parts[0] != "NativeRuns"
            or re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[0-9]+-[a-f0-9]{10}", parts[1]) is None
            or parts[2] != "derived" or parts[3] not in DERIVED_LANES or parts[4] not in REPRODUCIBLE_CACHES):
        return False
    # Unexpected original artifacts/logs nested in a build directory still belong
    # to the evidence. Unknown lanes/categories are retained as well.
    if any(p in {"Logs", "TestResults"} or p.endswith((".xcresult", ".xcarchive")) for p in parts[5:]):
        return False
    return not parts[-1].lower().endswith((".log", ".xcactivitylog"))


def evidence_index(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    members = {}
    omitted = {}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if candidate_git_metadata(relative):
            continue
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            continue
        if stat.S_ISLNK(info.st_mode):
            target = os.readlink(path)
            record = {"type": "symlink", "target": target, "mode": stat.S_IMODE(info.st_mode), "bytes": info.st_size,
                      "sha256": sha_bytes(os.fsencode(target)), "hash_scope": "link_target_bytes"}
        else:
            require(stat.S_ISREG(info.st_mode), "Unsupported evidence member")
            record = {"type": "file", "sha256": sha_file(path), "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode)}
        if reproducible_cache_member(relative):
            omitted[str(relative)] = record
        else:
            members[str(relative)] = record
    return members, omitted


def collect(control: Path, plan: dict[str, Any]) -> None:
    context, paths = ready(control, plan)
    require(not paths["evidence"].exists(), "Never replace a prior evidence package")
    paths["evidence"].mkdir(mode=0o700)
    issues = []
    try:
        check_seal(paths["stage"], read_json(paths["root"] / "STAGE-SEAL.json"))
    except (GateFailure, OSError) as error:
        issues.append(str(error))
    reports = list(paths["output"].glob("*/report.json")) if paths["output"].is_dir() else []
    report = {}
    if len(reports) != 1:
        issues.append("Exactly one actual native report was not produced")
    else:
        try:
            value = read_json(reports[0])
            require(isinstance(value, dict), "Native report is not a JSON object")
            report = value
        except (GateFailure, OSError, ValueError) as error:
            issues.append("Unreadable native report retained unchanged: " + str(error))
    passed = not issues and native_passed(report, plan["selection"], os.environ.get("LUMINA_NATIVE_STEP_OUTCOME", ""))
    if not passed and not issues:
        issues.append("Native report did not prove complete tests, archive verification and safe cleanup")
    if len(reports) == 1:
        folder = reports[0].parent / "lumina"
        for name in ("UIQATests.xcresult", "Production.xcarchive", "ProductionArchive.xcresult"):
            if not (folder / name).is_dir() or not any((folder / name).rglob("*")):
                passed = False
                issues.append("Missing original artifact: " + name)
    write_json(paths["root"] / "REMOTE-VERDICT.json", {"native_gate_passed": passed, "issues": issues,
               "source_commit": plan["config"]["candidate_commit"], "workflow_commit": context["GITHUB_SHA"],
               "native_step_outcome": os.environ.get("LUMINA_NATIVE_STEP_OUTCOME"),
               "upload_verified": False, "store_release": False,
               "scope": "Full 69+21 and unsigned archive evidence only; screenshots still require review."})
    index, omitted = evidence_index(paths["root"])
    write_json(paths["root"] / "EVIDENCE-INDEX.json", {"schema_version": 2, "members": index,
               "excluded_metadata_subtree": "Candidate/.git", "omitted_reproducible_cache_members": omitted,
               "omitted_cache_bytes": sum(v["bytes"] for v in omitted.values()),
               "omitted_cache_file_count": len(omitted), "required_original_evidence_omitted": False,
               "cache_policy": {"exact_derived_lanes": sorted(DERIVED_LANES), "exact_categories": sorted(REPRODUCIBLE_CACHES),
                                "xcresults_xcarchives_logs_TestResults_and_unknown_paths_retained": True}})
    archive = paths["evidence"] / "lumina-native-evidence.tar.gz"
    with tarfile.open(archive, "x:gz", dereference=False, compresslevel=6) as bundle:
        # Only present included members to tarfile. A skipped cache hardlink must
        # never become the stored inode target of a retained original artifact.
        for path in [paths["root"], *sorted(paths["root"].rglob("*"))]:
            relative = path.relative_to(paths["root"])
            if candidate_git_metadata(relative) or str(relative) in omitted:
                continue
            info = path.lstat()
            if not (stat.S_ISDIR(info.st_mode) or str(relative) in index or str(relative) == "EVIDENCE-INDEX.json"):
                unexpected = {
                    "relative_path": str(relative),
                    "type": "symlink" if stat.S_ISLNK(info.st_mode) else "file" if stat.S_ISREG(info.st_mode) else "unsupported",
                    "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode),
                    "mtime_ns": info.st_mtime_ns, "ctime_ns": info.st_ctime_ns,
                    "existing_cache_predicate": reproducible_cache_member(relative),
                    "was_in_retained_index": str(relative) in index, "was_in_omission_index": str(relative) in omitted,
                    "retained_index_count": len(index), "omission_index_count": len(omitted),
                    "diagnostic_only": True, "complete_native_evidence": False,
                }
                if stat.S_ISLNK(info.st_mode):
                    try:
                        unexpected["link_target"] = os.readlink(path)
                    except OSError as error:
                        unexpected["link_target_read_error"] = str(error)
                raise GateFailure("Unindexed evidence appeared during packaging: " + json.dumps(unexpected, ensure_ascii=False))
            name = "lumina-native-evidence" + ("/" + str(relative) if relative.parts else "")
            bundle.add(path, arcname=name, recursive=False)
    size = archive.stat().st_size
    digest = sha_file(archive)
    with tarfile.open(archive, "r:gz") as bundle:
        require(bundle.getmember("lumina-native-evidence/EVIDENCE-INDEX.json").isfile(), "Archive index missing")
        found = set()
        for member in bundle:
            if member.isdir():
                continue
            name = member.name.removeprefix("lumina-native-evidence/")
            require(member.name.startswith("lumina-native-evidence/") and name not in found,
                    "Unexpected or duplicate archived member")
            found.add(name)
            expected = index.get(name)
            if name == "EVIDENCE-INDEX.json":
                expected = {"type": "file", "sha256": sha_file(paths["root"] / name),
                            "mode": 0o600, "bytes": (paths["root"] / name).stat().st_size}
            require(expected is not None, "Unindexed evidence member")
            require(member.mode == expected["mode"], "Archived evidence mode mismatch")
            if member.issym():
                require(expected["type"] == "symlink" and member.linkname == expected["target"], "Archived link mismatch")
            elif member.isfile() or member.islnk():
                if member.islnk():
                    require(member.linkname.startswith("lumina-native-evidence/")
                            and ".." not in PurePosixPath(member.linkname).parts, "Unsafe archive hardlink")
                stream = bundle.extractfile(member)
                require(stream is not None, "Unreadable archived evidence")
                digest_check = hashlib.sha256()
                extracted_bytes = 0
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest_check.update(block)
                    extracted_bytes += len(block)
                require(expected["type"] == "file" and extracted_bytes == expected["bytes"]
                        and (member.islnk() or member.size == expected["bytes"])
                        and digest_check.hexdigest() == expected["sha256"], "Evidence archive byte mismatch")
            else:
                raise GateFailure("Unexpected archived evidence type")
        require(found == set(index) | {"EVIDENCE-INDEX.json"}, "Archive lost evidence members")
    write_json(paths["evidence"] / "TRANSFER-MANIFEST.json", {"archive": archive.name, "bytes": size, "sha256": digest,
               "source_commit": plan["config"]["candidate_commit"], "workflow_commit": context["GITHUB_SHA"],
               "run_id": context["GITHUB_RUN_ID"], "run_attempt": context["GITHUB_RUN_ATTEMPT"],
               "native_gate_passed": passed, "retention_days": 1, "upload_verified": False})
    require(size <= load_cost(plan)["maximum_artifact_bytes"],
            "Complete evidence exceeds the free cap; originals retained, no truncation or upload authorized")
    outputs({"upload_allowed": "true", "evidence_directory": str(paths["evidence"]),
             "archive_sha256": digest, "archive_bytes": str(size), "native_gate_passed": str(passed).lower()})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inspect", "prepare", "run", "collect"))
    parser.add_argument("--control-root", type=Path, required=True)
    args = parser.parse_args()
    control = args.control_root.resolve()
    try:
        plan = load_plan(control)
        if args.mode == "inspect":
            cost = load_cost(plan)
            print(json.dumps({"file_validation": "passed", "source_commit": plan["config"].get("candidate_commit"),
                  "native_authorization": plan["config"].get("native_authorization"), "source_files": len(plan["files"]),
                  "native_source_files": len(plan["native"]), "test_counts": COUNTS, "runner_sha256": RUNNER_SHA,
                  "private_cost_receipt_sha256": cost.get("private_verification_receipt_sha256"),
                  "native_invoked": False, "github_job_started": False}))
        elif args.mode == "prepare":
            prepare(control, plan)
        elif args.mode == "run":
            run_native(control, plan)
        else:
            collect(control, plan)
        return 0
    except (GateFailure, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print("REMOTE_CI_GATE_FAILED: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
