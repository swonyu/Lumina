"""Boundary checks for file bindings and the new remote wrapper; no native tools."""
import copy
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("remote_ci", Path(__file__).with_name("remote_ci.py"))
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


class RemoteGuardChecks(unittest.TestCase):
    def test_file_binding_rejects_changed_bytes_mode_extra_file_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "hook.sh"
            data = b"#!/bin/sh\nexit 0\n"
            path.write_bytes(data)
            path.chmod(0o755)
            expected = {"hook.sh": {"bytes": len(data), "sha256": ci.sha_bytes(data), "git_mode": "100755"}}
            ci.validate_files(root, expected)
            path.write_bytes(data.replace(b"0", b"1"))
            with self.assertRaises(ci.GateFailure): ci.validate_files(root, expected)
            path.write_bytes(data)
            path.chmod(0o644)
            with self.assertRaises(ci.GateFailure): ci.validate_files(root, expected)
            path.chmod(0o755)
            (root / "extra.swift").write_text("unexpected")
            with self.assertRaises(ci.GateFailure): ci.validate_files(root, expected)
            (root / "extra.swift").unlink()
            path.unlink()
            path.symlink_to("missing.sh")
            with self.assertRaises(ci.GateFailure): ci.validate_files(root, expected)

    def test_noncanonical_source_paths_and_duplicate_json_fail(self):
        for value in ("../escape", "/absolute", "a/../b", "a//b", ".git/config", "a\\b", "x\ny"):
            with self.subTest(value=value), self.assertRaises(ci.GateFailure): ci.relative_path(value)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.json"
            path.write_text('{"file":"one","file":"two"}')
            with self.assertRaises(ci.GateFailure): ci.read_json(path)

    def test_unbound_authority_and_changed_free_policy_fail_before_execution(self):
        now = dt.datetime(2026, 11, 18, tzinfo=dt.timezone.utc)
        config = {"candidate_commit": "a" * 40, "candidate_tree": "b" * 40,
                  "native_authorization": "ROOT_REVIEWED_GITHUB_VM_ONLY", "native_review_receipt_sha256": "c" * 64,
                  "repository": "swonyu/Lumina", "deadline_utc": "2026-11-18T22:26:12Z"}
        cost = {"schema_version": 1, "status": "ZERO_EXTRA_SPEND_VERIFIED", "repository": "swonyu/Lumina",
                "public_standard_runner_only": True, "extra_spending_permitted": False,
                "usage_blocked_at_zero_budget": True, "caches_allowed": False, "retention_days": 1,
                "maximum_artifact_bytes": ci.MAX_ARTIFACT_BYTES, "private_verification_receipt_sha256": "d" * 64}
        ci.validate_authority(config, cost, now)
        for key, value in (("candidate_commit", None), ("candidate_tree", "UNBOUND"),
                           ("native_authorization", "UNBOUND"), ("native_review_receipt_sha256", None)):
            bad = dict(config, **{key: value})
            with self.subTest(key=key), self.assertRaises(ci.GateFailure): ci.validate_authority(bad, cost, now)
        for key, value in (("extra_spending_permitted", True), ("usage_blocked_at_zero_budget", False),
                           ("caches_allowed", True), ("retention_days", 2), ("maximum_artifact_bytes", 1_000_000_000)):
            bad = dict(cost, **{key: value})
            with self.subTest(key=key), self.assertRaises(ci.GateFailure): ci.validate_authority(config, bad, now)
        with self.assertRaises(ci.GateFailure):
            ci.validate_authority(config, cost, dt.datetime(2026, 11, 18, 22, tzinfo=dt.timezone.utc))

    def test_full_case_and_archive_acceptance_rejects_partial_results(self):
        methods = {target: [target + "/fixture" + str(i) + "()" for i in range(count)] for target, count in ci.COUNTS.items()}
        selection = {"source_methods": methods}
        report = {"exit_code": 0, "cleanup_safe": True, "errors": [], "apps": ["lumina"], "skip_production": False,
                  "can_satisfy_full_lumina_test_gate": True, "lumina_test_scope": "FULL_90_CASE_TEST_GATE",
                  "app_results": {"lumina": {"status": "passed", "source_hashes_unchanged": True, "production_included": True}},
                  "source_manifest_status": "passed", "lumina_test_inventory": {"scope": "FULL_90_CASE_TEST_GATE",
                  "full_test_gate_passed": True, "test_counts": ci.COUNTS, "passed_test_identifiers": methods},
                  "lumina_test_counts": {"totalTestCount": 90, "passedTests": 90, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0},
                  "steps": [{"name": "lumina-release-archive-verifier", "status": "passed"}]}
        self.assertTrue(ci.native_passed(report, selection, "success"))
        for key, value in (("exit_code", False), ("cleanup_safe", False), ("skip_production", True), ("errors", ["interrupted"]),
                           ("source_manifest_status", "failed"), ("steps", []), ("can_satisfy_full_lumina_test_gate", False)):
            bad = dict(report, **{key: value})
            with self.subTest(key=key): self.assertFalse(ci.native_passed(bad, selection, "success"))
        bad = copy.deepcopy(report)
        bad["lumina_test_inventory"]["passed_test_identifiers"]["LuminaUITests"].pop()
        self.assertFalse(ci.native_passed(bad, selection, "success"))
        bad = copy.deepcopy(report)
        bad["lumina_test_counts"]["passedTests"] = 89
        self.assertFalse(ci.native_passed(bad, selection, "success"))
        self.assertFalse(ci.native_passed(report, selection, "cancelled"))
        self.assertFalse(ci.native_passed({"app_results": []}, selection, "success"))
        self.assertFalse(ci.native_passed({"lumina_test_inventory": []}, selection, "success"))
        self.assertFalse(ci.native_passed({"steps": [None]}, selection, "success"))

    def test_seal_detects_mode_change_and_directory_symlinks_are_indexed_without_following(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = root / "stage"
            stage.mkdir()
            (stage / "source.swift").write_text("source")
            seal = ci.stage_seal(stage)
            ci.check_seal(stage, seal)
            (stage / "source.swift").chmod(0o755)
            with self.assertRaises(ci.GateFailure): ci.check_seal(stage, seal)
            evidence = root / "evidence"
            evidence.mkdir()
            (evidence / "linked-directory").symlink_to(stage, target_is_directory=True)
            index, omitted = ci.evidence_index(evidence)
            self.assertEqual(set(index), {"linked-directory"})
            self.assertEqual(index["linked-directory"]["type"], "symlink")
            self.assertFalse(omitted)

    def test_non_hosted_environment_is_rejected_without_invoking_a_tool(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(ci.subprocess, "run") as process:
            with self.assertRaises(ci.GateFailure): ci.hosted_context({}, Path("/unused"))
            process.assert_not_called()

    def test_complete_evidence_pack_retains_raw_files_and_refuses_an_insufficient_cap(self):
        for cap, allowed in ((ci.MAX_ARTIFACT_BYTES, True), (1, False)):
            with self.subTest(cap=cap), tempfile.TemporaryDirectory() as directory:
                temporary = Path(directory)
                root = temporary / "run"
                stage = root / "Stage"
                stage.mkdir(parents=True)
                (stage / "source.swift").write_text("fixture source")
                ci.write_json(root / "STAGE-SEAL.json", ci.stage_seal(stage))
                native = root / "NativeRuns/20261118T000000Z-123-abcdef1234/lumina"
                native.mkdir(parents=True)
                for name in ("UIQATests.xcresult", "Production.xcarchive", "ProductionArchive.xcresult"):
                    (native / name).mkdir()
                    (native / name / "fixture.bin").write_bytes(b"original artifact fixture\x00")
                original = native / "UIQATests.xcresult/fixture.bin"
                os.link(original, native / "hardlinked-original.bin")
                cache = native.parent / "derived/lumina-uiqa/Build"
                cache.mkdir(parents=True)
                os.link(original, cache / "cache-copy.bin")
                (native / "artifact-reference").symlink_to("UIQATests.xcresult", target_is_directory=True)
                ci.write_json(native.parent / "report.json", {"exit_code": 143, "errors": ["fixture interruption"]})
                paths = {"root": root, "stage": stage, "output": root / "NativeRuns", "evidence": temporary / "evidence"}
                context = {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}
                plan = {"config": {"candidate_commit": "b" * 40}, "selection": {"source_methods": {}}}
                output = temporary / "github-output"
                with patch.object(ci, "ready", return_value=(context, paths)), \
                     patch.object(ci, "load_cost", return_value={"maximum_artifact_bytes": cap}), \
                     patch.dict(os.environ, {"GITHUB_OUTPUT": str(output), "LUMINA_NATIVE_STEP_OUTCOME": "failure"}):
                    if allowed:
                        ci.collect(temporary, plan)
                        self.assertIn("upload_allowed=true", output.read_text())
                        self.assertIn("native_gate_passed=false", output.read_text())
                    else:
                        with self.assertRaises(ci.GateFailure): ci.collect(temporary, plan)
                        self.assertFalse(output.exists())
                self.assertEqual(original.read_bytes(), b"original artifact fixture\x00")
                archive = paths["evidence"] / "lumina-native-evidence.tar.gz"
                self.assertTrue(archive.is_file())
                with tarfile.open(archive, "r:gz") as bundle:
                    member = "lumina-native-evidence/" + str(original.relative_to(root))
                    self.assertEqual(bundle.extractfile(member).read(), original.read_bytes())
                    self.assertNotIn("lumina-native-evidence/" + str((cache / "cache-copy.bin").relative_to(root)), bundle.getnames())

    def test_exact_cache_scope_protects_nested_originals_and_unknown_paths(self):
        run = "NativeRuns/20261118T000000Z-123-abcdef1234/"
        lane = run + "derived/lumina-uiqa/"
        omitted_paths = {lane + "Build/product.o", lane + "SDKExplicitPrecompiledModules/cache.pcm"}
        included_paths = {run + "lumina/.git/original.bin", "Candidate/.gitkeep",
            lane + "Build/nested.xcresult/data.bin", lane + "Build/nested.xcarchive/data.bin",
            lane + "Build/Logs/raw.bin", lane + "Build/TestResults/result.bin",
            lane + "Build/compiler.log", lane + "Build/compiler.xcactivitylog",
            lane + "UnknownCache/keep.bin", run + "derived/unknown-lane/Build/keep.o"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in omitted_paths | included_paths | {"Candidate/.git/config"}:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
            index, omitted = ci.evidence_index(root)
            self.assertEqual(set(index), included_paths)
            self.assertEqual(set(omitted), omitted_paths)
            for name, record in omitted.items():
                self.assertEqual(record["sha256"], ci.sha_file(root / name))
                self.assertEqual(record["bytes"], (root / name).stat().st_size)
                self.assertEqual(record["mode"], (root / name).stat().st_mode & 0o777)
                self.assertTrue((root / name).is_file(), "Omission is not deletion")

    def test_malformed_duplicate_wrong_shaped_and_missing_reports_preserve_originals(self):
        for raw in (b'{"exit_code":', b'{"exit_code":0,"exit_code":1}', b'[]', b'{"app_results":[]}', None):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as directory:
                temporary = Path(directory)
                root = temporary / "run"
                stage = root / "Stage"
                stage.mkdir(parents=True)
                (stage / "source.swift").write_text("fixture source")
                ci.write_json(root / "STAGE-SEAL.json", ci.stage_seal(stage))
                native = root / "NativeRuns/20261118T000000Z-123-abcdef1234/lumina"
                native.mkdir(parents=True)
                original = native / "UIQATests.xcresult/original.bin"
                original.parent.mkdir()
                original.write_bytes(b"interrupted original artifact")
                report = native.parent / "report.json"
                if raw is not None:
                    report.write_bytes(raw)
                paths = {"root": root, "stage": stage, "output": root / "NativeRuns", "evidence": temporary / "evidence"}
                context = {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}
                plan = {"config": {"candidate_commit": "b" * 40}, "selection": {"source_methods": {}}}
                output = temporary / "github-output"
                with patch.object(ci, "ready", return_value=(context, paths)), \
                     patch.object(ci, "load_cost", return_value={"maximum_artifact_bytes": ci.MAX_ARTIFACT_BYTES}), \
                     patch.dict(os.environ, {"GITHUB_OUTPUT": str(output), "LUMINA_NATIVE_STEP_OUTCOME": "failure"}):
                    ci.collect(temporary, plan)
                verdict = json.loads((root / "REMOTE-VERDICT.json").read_bytes())
                self.assertFalse(verdict["native_gate_passed"])
                self.assertTrue(verdict["issues"])
                self.assertIn("upload_allowed=true", output.read_text())
                with tarfile.open(paths["evidence"] / "lumina-native-evidence.tar.gz", "r:gz") as bundle:
                    prefix = "lumina-native-evidence/"
                    self.assertEqual(bundle.extractfile(prefix + str(original.relative_to(root))).read(), original.read_bytes())
                    if raw is not None:
                        self.assertEqual(bundle.extractfile(prefix + str(report.relative_to(root))).read(), raw)


if __name__ == "__main__":
    unittest.main(verbosity=2)
