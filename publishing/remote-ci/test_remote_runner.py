"""Remote-v4 runner boundary checks. No native subprocess or lock is allowed."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

HERE = Path(__file__).parent
SPEC = importlib.util.spec_from_file_location("remote_v8_runner", HERE / "Runner/verify_publishing.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
SELECTION = json.loads((HERE / "test-selection.json").read_text())
DEVICE = "D050DD76-290F-47F8-B03E-A08A1CF7802A"


def evidence_fixture():
    configuration = {"configurationId": "full90", "configurationName": "Functional acceptance"}
    device = {"deviceId": DEVICE, "platform": "iOS Simulator"}
    counts = {"passedTests": 90, "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
    summary = {**counts, "totalTestCount": 90, "result": "Passed", "testFailures": [],
               "devicesAndConfigurations": [{**counts, "device": device,
                                              "testPlanConfiguration": configuration}]}
    bundles = []
    for target, values in SELECTION["source_methods"].items():
        suites = {}
        for identifier in values:
            suite, method = identifier.split("/", 1)
            suites.setdefault(suite, []).append({"nodeType": "Test Case", "name": method,
                "nodeIdentifier": identifier, "result": "Passed", "durationInSeconds": 0.1,
                "nodeIdentifierURL": "test://com.apple.xcode/Lumina/" + target + "/" + identifier})
        bundles.append({"nodeType": "Unit test bundle" if target == "LuminaTests" else "UI test bundle",
                        "name": target, "result": "Passed", "children": [
                            {"nodeType": "Test Suite", "name": suite, "result": "Passed", "children": children}
                            for suite, children in suites.items()]})
    tree = {"devices": [device], "testPlanConfigurations": [configuration], "testNodes": [
        {"nodeType": "Test Plan", "name": "Lumina", "result": "Passed", "children": bundles}]}
    return summary, tree


def hosted_fixture(temporary):
    root = temporary / "lumina-native-123-1"
    env = {"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ARCH": "ARM64",
           "LUMINA_RUNNER_ENVIRONMENT": "github-hosted", "GITHUB_REPOSITORY": "swonyu/Lumina",
           "GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/continuation/publishing-r23-remote-ci-v9-d57",
           "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "RUNNER_TEMP": str(temporary),
           "DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer"}
    args = argparse.Namespace(apps=["lumina"], skip_production=False, advertising_preparation_root=None,
        deadline_minutes=75, lumina_scheme="Lumina AI personal trainer", sim_runtime_id="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        sim_device_name="iPhone 17 Pro", slot_authorized="github-123-1", lumina_root=root / "Stage/Source",
        halal_root=root / "UnusedHalalRoot", career_root=root / "UnusedCareerRoot", output_root=root / "NativeRuns",
        source_manifest=root / "Stage/Evidence/source-manifest.json")
    return root, env, args


class RemoteRunnerChecks(unittest.TestCase):
    def test_exact_current_source_plan_matches_all_90_runner_identities(self):
        self.assertEqual({key: sorted(value) for key, value in runner.EXPECTED_LUMINA_TESTS.items()},
                         SELECTION["source_methods"])
        self.assertEqual({key: len(value) for key, value in runner.EXPECTED_LUMINA_TESTS.items()},
                         {"LuminaTests": 69, "LuminaUITests": 21})

    def test_full_scope_requires_all_exact_cases_on_the_owned_device(self):
        summary, tree = evidence_fixture()
        result = runner.validate_lumina_test_evidence(summary, tree, expected_device_id=DEVICE)
        self.assertEqual(result["scope"], "FULL_90_CASE_TEST_GATE")
        self.assertIs(result["full_test_gate_passed"], True)
        self.assertEqual(result["passed_test_identifiers"], SELECTION["source_methods"])
        with self.assertRaises(runner.StageFailure):
            runner.validate_lumina_test_evidence(summary, tree, expected_device_id="another-device")
        cases = []
        missing = copy.deepcopy(tree)
        missing["testNodes"][0]["children"][0]["children"][0]["children"].pop()
        cases.append(missing)
        duplicate = copy.deepcopy(tree)
        leaves = duplicate["testNodes"][0]["children"][0]["children"][0]["children"]
        leaves.append(copy.deepcopy(leaves[0]))
        cases.append(duplicate)
        skipped = copy.deepcopy(tree)
        skipped["testNodes"][0]["children"][0]["children"][0]["children"][0]["result"] = "Skipped"
        cases.append(skipped)
        for index, changed in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(runner.StageFailure):
                runner.validate_lumina_test_evidence(summary, changed, expected_device_id=DEVICE)
        for key, value in [("totalTestCount", 82), ("failedTests", 1), ("skippedTests", 1), ("expectedFailures", 1)]:
            with self.subTest(key=key), self.assertRaises(runner.StageFailure):
                runner.validate_lumina_test_evidence({**summary, key: value}, tree, expected_device_id=DEVICE)

    def test_entry_rejects_local_partial_reused_and_out_of_stage_invocations(self):
        with tempfile.TemporaryDirectory() as directory:
            root, env, args = hosted_fixture(Path(directory).resolve())
            script = root / "Stage/Runner/verify_publishing.py"
            with patch.object(runner.sys, "platform", "darwin"), patch.object(runner, "__file__", str(script)), \
                 patch.dict(os.environ, env, clear=True):
                runner.validate_hosted_invocation(args)
                for key, value in [("LUMINA_RUNNER_ENVIRONMENT", "self-hosted"), ("GITHUB_ACTIONS", "false"),
                                   ("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_REPOSITORY", "other/repo"),
                                   ("GITHUB_REF", "refs/heads/continuation/publishing-r22-remote-ci-d57"),
                                   ("DEVELOPER_DIR", "/Applications/Other.app")]:
                    with self.subTest(key=key), patch.dict(os.environ, {key: value}), self.assertRaises(runner.StageFailure):
                        runner.validate_hosted_invocation(args)
                for key, value in [("apps", ["career"]), ("skip_production", True), ("deadline_minutes", 44),
                                   ("output_root", Path(directory) / "other"),
                                   ("source_manifest", Path(directory) / "other-manifest"),
                                   ("lumina_root", Path("relative")), ("slot_authorized", "old-local-slot")]:
                    changed = argparse.Namespace(**vars(args), **{})
                    setattr(changed, key, value)
                    with self.subTest(key=key), self.assertRaises(runner.StageFailure):
                        runner.validate_hosted_invocation(changed)
            with patch.object(runner, "arguments", return_value=args), patch.dict(os.environ, {}, clear=True), \
                 patch.object(runner, "Runner", side_effect=AssertionError("Native/output runner must not be constructed")):
                self.assertEqual(runner.main(), 2)
            self.assertFalse(root.exists())

    def test_native_command_contract_uses_full_plan_timeout_and_current_source_guards(self):
        # Supply an independently verified source tree via a test-only environment
        # variable. Without it this contract check fails; no skipped test is used.
        source_text = os.environ.get("LUMINA_REVIEW_SOURCE", "")
        self.assertTrue(source_text, "Set LUMINA_REVIEW_SOURCE to the verified R23 source for file-only review")
        source = Path(source_text)
        summary, tree = evidence_fixture()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "lumina/UIQATests.xcresult").mkdir(parents=True)
            calls = []
            class FixtureRunner:
                report = {}
                def __init__(self):
                    self.output = output
                    self.work_deadline = time.monotonic() + 5000
                def flush(self): pass
                def xcode_base(self, spec, lane, destination):
                    return ["xcodebuild", "-configuration", "Release", "-destination", destination]
                def create_simulator(self, root): return DEVICE
                def run(self, name, command, cwd, timeout, **kwargs):
                    calls.append((name, command, cwd, timeout, kwargs))
                    return {"status": "passed"}
                def json_command(self, name, command, cwd, timeout):
                    if name == "lumina-test-result-summary": return summary
                    if name == "lumina-test-result-tree": return tree
                    configuration = "Release" if name.endswith("release") else "UIQA"
                    return [{"target": "Lumina", "buildSettings": {"CONFIGURATION": configuration,
                        "WRAPPER_EXTENSION": "app", "PRODUCT_TYPE": "com.apple.product-type.application",
                        "PRODUCT_BUNDLE_IDENTIFIER": "SA.Lumina", "CODE_SIGNING_ALLOWED": "NO",
                        "PLATFORM_NAME": "iphoneos" if configuration == "Release" else "iphonesimulator",
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "" if configuration == "Release" else "UI_TESTING",
                        "ENABLE_TESTABILITY": "YES"}}]
            fixture = FixtureRunner()
            with patch.object(runner.subprocess, "Popen", side_effect=AssertionError("Native command forbidden")):
                runner.Runner.lumina_tests(fixture, {"root": source, "scheme": "Lumina AI personal trainer"})
            self.assertEqual(len(calls), 1)
            name, command, cwd, timeout, kwargs = calls[0]
            self.assertEqual((name, cwd, timeout, kwargs), ("lumina-uiqa-unit-ui-tests", source, 2700, {"check": False}))
            self.assertEqual(command[command.index("-testPlan") + 1], "Lumina AI personal trainer")
            self.assertFalse(any(item.startswith(("-only-testing", "-skip-testing", "-retry-tests", "-test-iterations")) for item in command))
            self.assertEqual(fixture.report["lumina_test_inventory"]["passed_test_identifiers"], SELECTION["source_methods"])
            self.assertEqual(fixture.report["lumina_test_counts"]["totalTestCount"], 90)


if __name__ == "__main__":
    unittest.main()
