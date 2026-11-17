#!/usr/bin/env python3
"""Serial, explicitly scheduled local QA. Never uploads, signs, or publishes.

Authoring status: prepared in the cloud; not executed on the Mac by its author.
Launch only after an acknowledged scheduling gap, with --slot-authorized TOKEN.
There is no lock wait, retry, stale reclamation, package install, or reacquisition.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import socket
import stat
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any
import uuid
import xml.etree.ElementTree as ET


LOCK_PATH = Path("/tmp/dot-ios-build.lock")
OWNER_FILE = "owner.json"
CLEANUP_RESERVE = 120.0
SOURCE_SUFFIXES = {
    ".swift", ".pbxproj", ".xcscheme", ".xcconfig", ".xcprivacy", ".plist",
    ".json", ".strings", ".stringsdict", ".xcstrings", ".storyboard", ".xib",
    ".entitlements", ".png", ".jpg", ".jpeg", ".svg", ".pdf", ".py", ".sh",
    # Career embeds Web resources in its native app. Their bytes are build inputs,
    # even when an asset was generated before this QA run (for example app.js).
    ".html", ".htm", ".css", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx",
    ".webmanifest", ".wasm", ".json5", ".xml", ".txt", ".yaml", ".yml", ".map", ".xctestplan",
    ".gif", ".webp", ".avif", ".ico", ".ttf", ".otf", ".woff", ".woff2",
    ".mp3", ".m4a", ".wav", ".ogg", ".mp4", ".webm", ".mov", ".vtt", ".srt",
    ".md", ".xcworkspacedata",
}
EXCLUDED_DIRS = {
    ".git", ".build", ".venv", "venv", "node_modules", "DerivedData",
    "BuildLogs", "build", "Build", "__pycache__", ".research", "xcuserdata",
}


def inventory_policy() -> dict[str, Any]:
    """The exact enumeration contract a complete baseline must declare."""
    return {"source_suffixes": sorted(SOURCE_SUFFIXES),
            "excluded_directories": sorted(EXCLUDED_DIRS),
            "included_filenames": ["Package.resolved"], "follow_symlinks": False}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".publishing-tmp")
    with temporary.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


class StageFailure(RuntimeError):
    pass


class BatchStopped(RuntimeError):
    pass


class Occupied(RuntimeError):
    pass


EXPECTED_LUMINA_TESTS = {
    'LuminaTests': frozenset({
        'JournalRecoveryIntegrityTests/canceledControllerRetainsAdmissionUntilItsActualWorkerStops()',
        'JournalRecoveryIntegrityTests/cancellationDeadlineAndSizeLimitsCleanOnlyOwnedStaging()',
        'JournalRecoveryIntegrityTests/failureBeforeCommitRollsBackEveryImportedModelAndCanRetry()',
        'JournalRecoveryIntegrityTests/forcedWALSnapshotReopensAloneWithMultiMegabytePhotos()',
        'JournalRecoveryIntegrityTests/oldMalformedViewSubstitutionAndFutureVersionFilesAreRejectedUnchanged()',
        'JournalRecoveryIntegrityTests/restoreRefusesNonemptyDirtyAndReadOnlyJournalsWithoutMutation()',
        'JournalRecoveryIntegrityTests/transactionalRestorePreservesAllFieldsRelationshipsAndUndoAfterReopen()',
        'JournalRecoveryIntegrityTests/typedRecordsRejectUnknownFieldsDuplicateIDsDanglingOwnersAndDeepJSON()',
        'JournalRecoveryIntegrityTests/typedRecoveryAndRawSnapshotShareOneCommittedState()',
        'LocalizationIntegrityTests/preferredLanguageAndSavedChoiceStayInTheirOwnPreferenceStore()',
        'OnDeviceCoachTests/frameworkAvailabilityMappingRetainsEveryReason()',
        'OnDeviceCoachTests/unavailableModelsNeverGenerateAndKeepUsefulEnglishAndArabicRules()',
        'OnDeviceCoachTests/successfulReplyHasTrueProvenanceAndExcludesUnverifiedHistory()',
        'OnDeviceCoachTests/boundedPromptPreservesWholeNumericLinesAndDisclosesEveryExcerpt()',
        'OnDeviceCoachTests/overlongQuestionIsNotSilentlyTruncatedOrSentToTheModel()',
        'OnDeviceCoachTests/refusalReturnsANoticeWithoutRetryingTrainingRules()',
        'OnDeviceCoachTests/operationalErrorsAndEmptyAnswersUseTruthfulLocalFallbacks()',
        'OnDeviceCoachTests/cancellationBeforeAdmissionDoesNotGenerateOrInventAReply()',
        'OnDeviceCoachTests/cancelledSlowRequestHoldsAdmissionUntilItActuallyTerminates()',
        'OnDeviceCoachTests/timeoutReturnsPromptlyWithoutOverlappingOrAcceptingLateGeneration()',
        'LuminaTests/offlineStoragePreservesDefaultLocation()',
        'LuminaTests/launchPreservesRecordsWithoutInventingSamples()',
        'LuminaTests/streaksUseConsecutiveDatesAndResetAfterGaps()',
        'LuminaTests/suggestedHabitPersistsWithoutInventingACompletion()',
        'LuminaTests/trainingSuggestionDescribesTheAvailableMeasurements()',
        'LuminaTests/databaseBackupRoundTripsRecordsAndDeletionIsIsolated()',
        'LuminaTests/offlineFollowUpSeparatesCheckInsFromHabitCompletions()',
        'LuminaTests/releaseCoachingDoesNotRequireCloudCredentials()',
        'PhotoImportIntegrityTests/laterSelectionWinsWhenEarlierLoaderFinishesLast()',
        'PhotoImportIntegrityTests/canceledLoaderCannotRefillClearedMealDraft()',
        'PhotoImportIntegrityTests/leavingScreenCancelsPendingPhotoWithoutDiscardingCompletedPhoto()',
        'PhotoImportIntegrityTests/deletionInvalidatesImportAndStaleModelWrites()',
        'PhotoImportIntegrityTests/emptyOrFailedImportNeverBecomesASavablePhoto()',
        'SavedRecordIntegrityTests/activeHabitUniquenessIncludesOlderRecordsAndBothAddPaths()',
        'SavedRecordIntegrityTests/habitEditsPreserveCountersAndRejectDuplicateReactivation()',
        'SavedRecordIntegrityTests/canceledDraftsDoNotWriteOrLoseSavedPhotoAndSetData()',
        'SavedRecordIntegrityTests/savedEditsRoundTripAllFieldsAndKeepIdentitiesOwners()',
        'SavedRecordIntegrityTests/invalidEditsKeepSavedValuesAndTransactionFailureRollsBack()',
        'SavedRecordIntegrityTests/readOnlyAndRetiredSessionsRejectEditingAndIndividualDeletion()',
        'SavedRecordIntegrityTests/individualDeletionPreservesOtherRecordsAndIndependentBackup()',
        'SavedRecordIntegrityTests/numericDraftsRejectMalformedValuesAndPreserveSetIdentifiers()',
        'HabitUndoIntegrityTests/undoAfterGapRestoresExactPriorStateAcrossReopen()',
        'HabitUndoIntegrityTests/undoRestoresNewPersonalBestAndFirstCompletionExactly()',
        'HabitUndoIntegrityTests/nextDayUndoRestoresOnlyTheMostRecentCompletion()',
        'HabitUndoIntegrityTests/failedCompletionTransactionCannotLeaveUndoStateOrCountersBehind()',
        'HabitUndoIntegrityTests/previousHabitSchemaMigratesWithoutChangingSavedHistory()',
        'CoachContextIntegrityTests/editedLargeProteinSurvivesReopenAndOfflineReply()',
        'CoachContextIntegrityTests/summaryHandlesOverflowAndInvalidLegacyNumbersWithoutChangingRecords()',
        'CoachContextIntegrityTests/summaryStatesRecordScopeAndDistinguishesMissingProteinFromZero()',
        'CoachContextIntegrityTests/localizedArgumentsPreserveValuesTypesAndOrder()',
        'CoachContextIntegrityTests/localizedTextWithoutArgumentsRetainsLiteralPercentSigns()',
        'SettingsIntegrityTests/turningOffDuringPermissionCannotReenableTheReminder()',
        'SettingsIntegrityTests/anAddFinishingAfterOffRemovesItsOwnRequest()',
        'SettingsIntegrityTests/staleAddCleanupCannotRemoveANewerEnabledReminder()',
        'SettingsIntegrityTests/deletingTheJournalInvalidatesPendingReminderPermission()',
        'SettingsIntegrityTests/lateStartupCannotSupersedeAUserPermissionRequest()',
        'SettingsIntegrityTests/startupUsesTheInjectedPreferenceAndReconcilesOnlyItsRequests()',
        'SettingsIntegrityTests/deniedAuthorizationLeavesAnAccurateDisabledPreference()',
        'SettingsIntegrityTests/failedSchedulingDoesNotLeaveAFalseEnabledState()',
        'SettingsIntegrityTests/trainingObservationsUseTheLatestPersistedCheckIns()',
        'SettingsIntegrityTests/healthObservationWindowDoesNotUseOlderExcludedSnapshots()',
    }),
    'LuminaUITests': frozenset({
        'LuminaUITests/testRecoveryPreviewFixtureConfirmationReopenAndPickerCancelPaths()',
        'LuminaUITests/testLanguageChoiceUpdatesVisibleFlowsAndPersistsWithoutLosingDrafts()',
        'LuminaUITests/testNavigationAndDataControlCancelPaths()',
        'LuminaUITests/testVeryLargeTextExpandsJournalRows()',
        'LuminaUITests/testHomeAccessibilityAudit()',
        'LuminaUITests/testSaveRelaunchAndDeleteOnlyIsolatedFixtureRecords()',
        'LuminaUITests/testPrivacyInformationAtLargestTextAndBackNavigation()',
        'LuminaUITests/testSuggestedHabitPersistsWithoutAutomaticCompletion()',
        'LuminaUITests/testFinalHomeLinkRemainsReachableAboveTabBar()',
        'LuminaUITests/testFullJournalEditCancelAndRelaunch()',
        'LuminaUITests/testGoalValuesEditRelaunchAndConfirmedDeletion()',
        'LuminaUITests/testAllSavedMealsRemainEditableBeyondTheRecentPreview()',
        'LuminaUITests/testWorkoutExercisesSetsAndNotesRemainEditableAfterRelaunch()',
        'LuminaUITests/testWorkoutEffortIsOptionalAndExplicitRatingSurvivesDraftLanguageAndRelaunch()',
        'LuminaUITests/testManualHabitDuplicateErrorAndManagementPreserveRecords()',
        'LuminaUITests/testSavedCheckInNoteEditRelaunchAndDeletion()',
        'LuminaUITests/testDirectProgressAndSavedCheckInObservationRemainReachable()',
        'LuminaUITests/testOfflineCoachAcceptsMessageAndShowsLocalReply()',
    }),
}

EXPECTED_LUMINA_SUITES = {
    "LuminaTests": frozenset({"LuminaTests", "PhotoImportIntegrityTests", "SavedRecordIntegrityTests", "SettingsIntegrityTests", "CoachContextIntegrityTests", "HabitUndoIntegrityTests", "OnDeviceCoachTests", "LocalizationIntegrityTests", "JournalRecoveryIntegrityTests"}),
    "LuminaUITests": frozenset({"LuminaUITests"}),
}


def validate_lumina_ci_sources(root: Path, scheme_name: str) -> dict[str, Any]:
    """Require the explicit functional plan and safe scheme action separation."""
    if "/" in scheme_name or "\\" in scheme_name:
        raise StageFailure("Lumina scheme name is not a simple shared-scheme name")
    scheme_path = root / "Lumina.xcodeproj" / "xcshareddata" / "xcschemes" / (scheme_name + ".xcscheme")
    scheme = ET.parse(scheme_path).getroot()
    test_action, archive_action = scheme.find("TestAction"), scheme.find("ArchiveAction")
    if (test_action is None or test_action.get("buildConfiguration") != "UIQA"
            or archive_action is None or archive_action.get("buildConfiguration") != "Release"):
        raise StageFailure("Lumina TestAction must use UIQA and ArchiveAction must use Release")
    plans = test_action.findall("./TestPlans/TestPlanReference")
    if (len(plans) != 1 or plans[0].get("reference") != "container:Lumina AI personal trainer.xctestplan"
            or plans[0].get("default") != "YES" or test_action.find("Testables") is not None):
        raise StageFailure("Lumina scheme must select exactly the explicit default TestPlan")
    plan = json.loads((root / "Lumina AI personal trainer.xctestplan").read_text())
    if (not isinstance(plan, dict)
            or set(plan) != {"configurations", "defaultOptions", "testTargets", "version"}
            or type(plan.get("version")) is not int or plan["version"] != 1
            or plan.get("defaultOptions") != {}):
        raise StageFailure("Lumina TestPlan has unreviewed shared options or format")
    configurations = plan.get("configurations")
    if (not isinstance(configurations, list) or len(configurations) != 1
            or not isinstance(configurations[0], dict)
            or set(configurations[0]) != {"id", "name", "options"}
            or configurations[0].get("options") != {}
            or configurations[0].get("name") != "Functional acceptance"):
        raise StageFailure("Lumina TestPlan must have one unmodified functional configuration")
    try:
        uuid.UUID(configurations[0]["id"])
    except (ValueError, TypeError, AttributeError):
        raise StageFailure("Lumina TestPlan configuration ID is not a UUID")
    targets = plan.get("testTargets")
    expected_ids = {"LuminaTests": "4CEBA1A82FC7872D00A3C883", "LuminaUITests": "4CEBA1B22FC7872D00A3C883"}
    if not isinstance(targets, list) or len(targets) != 2:
        raise StageFailure("Lumina TestPlan must contain exactly the unit and UI targets")
    seen = set()
    for entry in targets:
        if not isinstance(entry, dict) or entry.get("parallelizable") is not False:
            raise StageFailure("Lumina TestPlan target has skipped, parallel or unreviewed options")
        target = entry.get("target")
        if not isinstance(target, dict) or set(target) != {"containerPath", "identifier", "name"}:
            raise StageFailure("Lumina TestPlan target reference is malformed")
        name = target.get("name")
        if (name not in expected_ids or name in seen
                or target.get("identifier") != expected_ids[name]
                or target.get("containerPath") != "container:Lumina.xcodeproj"):
            raise StageFailure("Lumina TestPlan target does not match the reviewed project")
        expected_keys = {"parallelizable", "target"}
        if name == "LuminaUITests":
            expected_keys.add("selectedTests")
        if set(entry) != expected_keys:
            raise StageFailure("Lumina TestPlan unit target must be unfiltered and UI target explicitly selected")
        # Swift Testing uses hierarchical per-test identifiers; the complete
        # sealed unit target avoids cross-framework name-filter omissions.
        # validate_lumina_test_sources still requires exactly 61 unit cases in nine sealed files,
        # and the native evidence guard requires every 61+18 leaf.
        if name == "LuminaUITests":
            selected = entry.get("selectedTests")
            if (not isinstance(selected, list) or not all(isinstance(x, str) for x in selected)
                    or len(selected) != len(set(selected)) or set(selected) != EXPECTED_LUMINA_TESTS[name]):
                raise StageFailure("Lumina TestPlan does not select the exact reviewed eighteen UI tests")
        seen.add(name)
    return {"test_configuration": "UIQA", "archive_configuration": "Release", "test_plan": "Lumina AI personal trainer",
            "selected_counts": {name: len(values) for name, values in EXPECTED_LUMINA_TESTS.items()},
            "selection_modes": {"LuminaTests": "entire sealed 61-case target",
                                "LuminaUITests": "eighteen explicit XCTest methods"}}


def validate_lumina_ci_build_settings(value: Any, configuration: str) -> dict[str, Any]:
    """Check actual Xcode settings; never supply the settings being proved."""
    if configuration not in {"Release", "UIQA"} or not isinstance(value, list) or not value:
        raise StageFailure("Lumina CI settings are empty or have an unknown configuration")
    app_settings = []
    for row in value:
        if not isinstance(row, dict) or not isinstance(row.get("buildSettings"), dict):
            raise StageFailure("Lumina CI build settings are malformed")
        build = row["buildSettings"]
        if build.get("CONFIGURATION") != configuration:
            raise StageFailure("Lumina CI settings were evaluated for the wrong configuration")
        for flag in ["SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_SWIFT_FLAGS"]:
            raw = build.get(flag, "")
            if not isinstance(raw, str):
                raise StageFailure("Lumina CI compiler flags have an unexpected type")
            if configuration == "Release" and "UI_TESTING" in raw:
                raise StageFailure("Release contains UI_TESTING; production configuration blocked")
            if configuration == "UIQA" and re.search(r"(?:^|\s)(?:-D\s*)?DEBUG(?:$|\s)", raw):
                raise StageFailure("UIQA unexpectedly enables DEBUG and would omit release-only tests")
        if build.get("WRAPPER_EXTENSION") == "app" and build.get("PRODUCT_TYPE") == "com.apple.product-type.application":
            if row.get("target") != "Lumina" or build.get("PRODUCT_BUNDLE_IDENTIFIER") != "SA.Lumina":
                raise StageFailure("Lumina CI app identity does not match the reviewed target")
            app_settings.append(build)
    if len(app_settings) != 1:
        raise StageFailure("Cannot identify exactly one Lumina app in CI settings")
    app = app_settings[0]
    expected_platform = "iphoneos" if configuration == "Release" else "iphonesimulator"
    if (app.get("PLATFORM_NAME") != expected_platform
            or app.get("CODE_SIGNING_ALLOWED") != "NO"):
        raise StageFailure("Lumina CI settings have the wrong platform or unexpected signing")
    if app.get("ICLOUD_CONTAINER_ENVIRONMENT"):
        raise StageFailure("Offline Lumina must not define an unused iCloud environment")
    if configuration == "UIQA":
        if ("UI_TESTING" not in app.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
                or app.get("ENABLE_TESTABILITY") != "YES"):
            raise StageFailure("UIQA must enable isolated app testing and testability in project settings")
    keys = ["CONFIGURATION", "PRODUCT_BUNDLE_IDENTIFIER", "PLATFORM_NAME", "CODE_SIGNING_ALLOWED",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_SWIFT_FLAGS", "ENABLE_TESTABILITY",
            "ICLOUD_CONTAINER_ENVIRONMENT"]
    return {key: app.get(key) for key in keys}


def validate_lumina_test_sources(root: Path) -> None:
    """Require exactly the reviewed nine Swift Testing files and one selected UI suite.

    Source declarations supplement, and never replace, the exact executed leaves.
    The unit target remains unfiltered; extra unit source files fail before Xcode.
    """
    unit_paths = {p.relative_to(root / "LuminaTests").as_posix()
                  for p in (root / "LuminaTests").rglob("*.swift")}
    required_units = {name + ".swift" for name in EXPECTED_LUMINA_SUITES["LuminaTests"]}
    if unit_paths != required_units:
        raise StageFailure("Lumina unit source file set differs from the reviewed nine suites")
    for target, suites in EXPECTED_LUMINA_SUITES.items():
        identifiers = []
        for suite in sorted(suites):
            path = root / target / (suite + ".swift")
            if path.is_symlink() or not path.is_file():
                raise StageFailure("Lumina test source must be an owned regular file")
            source = path.read_text()
            declaration = r"^\s*struct\s+" if target == "LuminaTests" else r"^\s*(?:final\s+)?class\s+"
            if len(re.findall(declaration + re.escape(suite) + r"\b", source, re.MULTILINE)) != 1:
                raise StageFailure("Lumina test suite declaration differs")
            pattern = r"^\s*@Test\s+func\s+(\w+)\s*\(" if target == "LuminaTests" else r"^\s*func\s+(test\w+)\s*\("
            names = re.findall(pattern, source, re.MULTILINE)
            identifiers.extend(suite + "/" + name + "()" for name in names)
        if len(identifiers) != len(set(identifiers)) or set(identifiers) != EXPECTED_LUMINA_TESTS[target]:
            raise StageFailure(f"{target} source inventory changed; review expected tests before QA")


def validate_lumina_test_evidence(summary: Any, tree: Any, *,
                                  expected_device_id: str | None = None) -> dict[str, Any]:
    """Require every reviewed test to have passed exactly once on the owned device.

    The schema is grounded in xcresulttool output from the retained, finalized
    QA-Isolated-Final.xcresult. Unknown shapes/statuses fail closed for review.
    Historical evidence cannot satisfy the current 61-unit/18-UI suite.
    """
    expected_count = sum(len(tests) for tests in EXPECTED_LUMINA_TESTS.values())
    if not isinstance(summary, dict) or not isinstance(tree, dict):
        raise StageFailure("Lumina test evidence must contain summary and tree objects")

    def require_counts(value: dict[str, Any], *, include_total: bool) -> None:
        counts = {"passedTests": expected_count, "failedTests": 0,
                  "skippedTests": 0, "expectedFailures": 0}
        if include_total:
            counts["totalTestCount"] = expected_count
        for key, expected in counts.items():
            if type(value.get(key)) is not int or value[key] != expected:
                raise StageFailure(f"Lumina {key} must be exactly {expected}; got {value.get(key)!r}")

    require_counts(summary, include_total=True)
    if summary.get("result") != "Passed" or summary.get("testFailures") != []:
        raise StageFailure("Lumina summary did not report a clean Passed result")
    configurations = summary.get("devicesAndConfigurations")
    devices = tree.get("devices")
    plans = tree.get("testPlanConfigurations")
    if not isinstance(configurations, list) or len(configurations) != 1 or not isinstance(configurations[0], dict):
        raise StageFailure("Lumina summary must identify exactly one device/configuration")
    require_counts(configurations[0], include_total=False)
    if not isinstance(devices, list) or len(devices) != 1 or not isinstance(devices[0], dict):
        raise StageFailure("Lumina tree must identify exactly one test device")
    device = configurations[0].get("device")
    identifier = devices[0].get("deviceId")
    if (not isinstance(device, dict) or not isinstance(identifier, str) or not identifier
            or device.get("deviceId") != identifier
            or device.get("platform") != "iOS Simulator"
            or devices[0].get("platform") != "iOS Simulator"
            or (expected_device_id is not None and identifier.upper() != expected_device_id.upper())):
        raise StageFailure("Lumina summary/tree device does not match the owned test simulator")
    configuration = configurations[0].get("testPlanConfiguration")
    if (not isinstance(plans, list) or len(plans) != 1 or not isinstance(plans[0], dict)
            or not isinstance(configuration, dict)
            or not isinstance(configuration.get("configurationId"), str)
            or not configuration["configurationId"]
            or configuration != plans[0]):
        raise StageFailure("Lumina summary/tree test configurations do not match")

    roots = tree.get("testNodes")
    if not isinstance(roots, list) or len(roots) != 1:
        raise StageFailure("Lumina tree must contain exactly one test plan")
    found: dict[str, set[str]] = {target: set() for target in EXPECTED_LUMINA_TESTS}
    bundles: set[str] = set()
    suites: dict[str, set[str]] = {target: set() for target in EXPECTED_LUMINA_SUITES}

    def walk(node: Any, parent: str | None = None, target: str | None = None,
             suite: str | None = None) -> None:
        if not isinstance(node, dict) or node.get("result") != "Passed":
            raise StageFailure("Lumina test tree contains a missing, skipped or non-passing result")
        kind = node.get("nodeType")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise StageFailure("Lumina test tree has malformed children")
        if kind == "Test Plan":
            if parent is not None or len(children) != len(EXPECTED_LUMINA_TESTS):
                raise StageFailure("Lumina test plan has an unexpected structure")
        elif kind in {"Unit test bundle", "UI test bundle"}:
            target = node.get("name")
            if (parent != "Test Plan" or target not in EXPECTED_LUMINA_TESTS or target in bundles
                    or kind != ("Unit test bundle" if target == "LuminaTests" else "UI test bundle")
                    or len(children) != len(EXPECTED_LUMINA_SUITES[target])):
                raise StageFailure("Lumina tree has an unexpected or duplicate test bundle")
            bundles.add(target)
        elif kind == "Test Suite":
            suite = node.get("name")
            if (parent not in {"Unit test bundle", "UI test bundle"}
                    or target not in EXPECTED_LUMINA_SUITES
                    or suite not in EXPECTED_LUMINA_SUITES[target] or suite in suites[target]
                    or not children):
                raise StageFailure("Lumina tree has an unexpected or duplicate test suite")
            suites[target].add(suite)
        elif kind == "Test Case":
            test_id = node.get("nodeIdentifier")
            if (parent != "Test Suite" or target is None or children
                    or not isinstance(test_id, str) or test_id not in EXPECTED_LUMINA_TESTS[target]
                    or test_id.split("/", 1)[0] != suite
                    or node.get("name") != test_id.split("/", 1)[1]):
                raise StageFailure(f"Lumina tree has an unexpected or malformed test leaf: {test_id!r}")
            if test_id in found[target]:
                raise StageFailure(f"Lumina test leaf ran more than once: {test_id}")
            test_url = node.get("nodeIdentifierURL")
            expected_url = f"test://com.apple.xcode/Lumina/{target}/{test_id}"
            if (not isinstance(test_url, str)
                    or test_url.removesuffix("()") != expected_url.removesuffix("()")):
                raise StageFailure(f"Lumina test identifiers disagree: {test_id}")
            duration = node.get("durationInSeconds")
            if type(duration) not in {int, float} or not 0 <= duration < float("inf"):
                raise StageFailure(f"Lumina test leaf lacks a valid execution duration: {test_id}")
            found[target].add(test_id)
        else:
            raise StageFailure(f"Unrecognized Lumina test-tree node type: {kind!r}")
        for child in children:
            walk(child, kind, target, suite)

    walk(roots[0])
    if (bundles != set(EXPECTED_LUMINA_TESTS)
            or any(suites[target] != expected for target, expected in EXPECTED_LUMINA_SUITES.items())):
        raise StageFailure("Lumina tree did not prove all eight expected test suites")
    for target, expected in EXPECTED_LUMINA_TESTS.items():
        missing = expected - found[target]
        if missing:
            raise StageFailure(f"Lumina tests were not executed: {', '.join(sorted(missing))}")
    return {"device_id": identifier, "test_counts": {target: len(tests) for target, tests in found.items()},
            "passed_test_identifiers": {target: sorted(tests) for target, tests in found.items()}}


class BuildLock:
    """Only release the directory inode and exact metadata this process created."""

    def __init__(self, run_id: str, slot: str, output: Path):
        self.record = {
            "owner": "ios-app-publishing-and-quality",
            "marker": "publishing:" + run_id,
            "pid": os.getpid(),
            "host": socket.gethostname(),
            "started_at": utc_now(),
            "slot_authorized": slot,
            "output": str(output),
        }
        self.payload = (json.dumps(self.record, sort_keys=True) + "\n").encode()
        self.acquired = False
        self.directory_identity: tuple[int, int] | None = None
        self.owner_identity: tuple[int, int] | None = None

    def acquire(self) -> None:
        try:
            os.mkdir(LOCK_PATH, 0o700)
        except FileExistsError:
            raise Occupied(f"Shared build slot occupied: {LOCK_PATH}; no wait or reclamation attempted")
        self.acquired = True
        metadata = LOCK_PATH.lstat()
        self.directory_identity = (metadata.st_dev, metadata.st_ino)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        descriptor = os.open(LOCK_PATH / OWNER_FILE, flags, 0o600)
        try:
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(self.payload)
                handle.flush()
                os.fsync(handle.fileno())
                metadata = os.fstat(handle.fileno())
                self.owner_identity = (metadata.st_dev, metadata.st_ino)
        except BaseException:
            # Without exact metadata proof, retain the directory for the owner.
            raise

    def release(self) -> tuple[bool, str]:
        if not self.acquired:
            return True, "No lock acquired"
        try:
            directory = LOCK_PATH.lstat()
            if not stat.S_ISDIR(directory.st_mode) or (directory.st_dev, directory.st_ino) != self.directory_identity:
                return False, "Lock directory identity changed; retained"
            descriptor = os.open(LOCK_PATH, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                directory = os.fstat(descriptor)
                if (directory.st_dev, directory.st_ino) != self.directory_identity:
                    return False, "Opened directory identity changed; retained"
                names = os.listdir(descriptor)
                if names != [OWNER_FILE]:
                    return False, "Unexpected lock-directory contents; retained without deleting any file"
                owner = os.stat(OWNER_FILE, dir_fd=descriptor, follow_symlinks=False)
                if not stat.S_ISREG(owner.st_mode) or (owner.st_dev, owner.st_ino) != self.owner_identity:
                    return False, "Owner metadata identity changed; retained"
                owner_fd = os.open(OWNER_FILE, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=descriptor)
                with os.fdopen(owner_fd, "rb") as handle:
                    if handle.read() != self.payload:
                        return False, "Owner metadata bytes changed; retained"
                current = LOCK_PATH.lstat()
                if (current.st_dev, current.st_ino) != self.directory_identity:
                    return False, "Lock path was replaced; retained"
                os.unlink(OWNER_FILE, dir_fd=descriptor)
                try:
                    current = LOCK_PATH.lstat()
                    if (current.st_dev, current.st_ino) != self.directory_identity:
                        return False, "Lock path changed after own metadata removal; no directory removed"
                    os.rmdir(LOCK_PATH)
                except OSError as error:
                    # Restore only our exact marker, only in our still-open inode.
                    try:
                        marker_fd = os.open(OWNER_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                            0o600, dir_fd=descriptor)
                        with os.fdopen(marker_fd, "wb") as handle:
                            handle.write(self.payload)
                            handle.flush()
                            os.fsync(handle.fileno())
                    except OSError:
                        pass
                    return False, f"Own directory could not be removed; retained: {error}"
            finally:
                os.close(descriptor)
            self.acquired = False
            return True, "Exact own metadata removed and own lock directory released"
        except OSError as error:
            return False, f"Ownership verification failed; lock retained: {error}"


class Runner:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.run_id = uuid.uuid4().hex
        label = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self.output = args.output_root.expanduser().resolve() / f"{label}-{os.getpid()}-{self.run_id[:10]}"
        self.output.mkdir(parents=True, mode=0o700, exist_ok=False)
        self.started = time.monotonic()
        self.deadline = self.started + args.deadline_minutes * 60
        self.work_deadline = self.deadline - CLEANUP_RESERVE
        self.cancel_signal: int | None = None
        self.owned: list[dict[str, Any]] = []
        self.sequence = 0
        self.simulator: str | None = None
        self.simulator_name = "Publishing-Lumina-" + self.run_id[:16]
        self.preexisting_devices: set[str] = set()
        self.simulator_create_attempted = False
        self.simulator_boot_attempted = False
        self.simulator_discovery_known = False
        self.lock = BuildLock(self.run_id, args.slot_authorized, self.output)
        self.report: dict[str, Any] = {
            "run_id": self.run_id, "pid": os.getpid(), "started_at": utc_now(),
            "apps": args.apps, "skip_production": args.skip_production,
            "deadline_minutes": args.deadline_minutes, "cleanup_reserve_seconds": CLEANUP_RESERVE,
            "slot_authorized": args.slot_authorized, "steps": [], "errors": [],
            "app_results": {}, "lock": "not acquired", "simulator": None,
            "limits": ["No manual VoiceOver or all-screen acceptance", "No physical-device acceptance",
                       "Unsigned local artifacts only", "No signing, upload, App Review or public-release claim"],
        }
        self.flush()

    def flush(self) -> None:
        write_json(self.output / "report.json", self.report)

    def error(self, stage: str, message: str) -> None:
        self.report["errors"].append({"stage": stage, "message": message, "at": utc_now()})
        self.flush()

    def checkpoint(self, cleanup: bool = False) -> None:
        if not cleanup and self.cancel_signal is not None:
            raise BatchStopped(f"Signal {self.cancel_signal} requested cancellation")
        limit = self.deadline if cleanup else self.work_deadline
        if time.monotonic() >= limit:
            raise BatchStopped("Batch work deadline reached; remaining time is reserved for cleanup")

    @staticmethod
    def group_exists(pgid: int) -> bool:
        try:
            os.killpg(pgid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def stop_owned(self, child: dict[str, Any]) -> bool:
        """No process-name matching: only the session/process group we spawned."""
        if child["closed"]:
            return True  # Never revisit a retired PGID that the OS could reuse.
        process: subprocess.Popen = child["process"]
        pgid = child["pgid"]
        process.poll()
        for sig, grace in [(signal.SIGTERM, 10.0), (signal.SIGKILL, 5.0)]:
            if not self.group_exists(pgid):
                break
            try:
                os.killpg(pgid, sig)
                child["signals"].append({"signal": sig, "at": utc_now()})
            except ProcessLookupError:
                break
            except PermissionError:
                return False
            stop_at = min(time.monotonic() + grace, self.deadline)
            while self.group_exists(pgid) and time.monotonic() < stop_at:
                process.poll()  # Reap our direct child when it has exited.
                time.sleep(0.15)
        process.poll()
        if process.poll() is None:
            return False
        process.wait(timeout=0)
        child["closed"] = not self.group_exists(pgid)
        return child["closed"]

    def run(self, name: str, command: list[str], cwd: Path, timeout: float,
            *, cleanup: bool = False, check: bool = True) -> dict[str, Any]:
        self.checkpoint(cleanup)
        self.sequence += 1
        stage = self.output / "steps" / f"{self.sequence:03d}-{name}"
        stage.mkdir(parents=True, exist_ok=False)
        limit = self.deadline if cleanup else self.work_deadline
        allowed = min(timeout, limit - time.monotonic())
        if allowed <= 0:
            raise BatchStopped("No time remains for this stage")
        temporary = self.output / "tmp" / name
        temporary.mkdir(parents=True, exist_ok=True)
        environment = os.environ.copy()
        environment.update({"TMPDIR": str(temporary) + "/", "NSUnbufferedIO": "YES"})
        item: dict[str, Any] = {
            "name": name, "argv": [str(x) for x in command], "cwd": str(cwd),
            "environment_overrides": {"TMPDIR": environment["TMPDIR"], "NSUnbufferedIO": "YES"},
            "timeout_seconds": allowed, "started_at": utc_now(),
            "stdout": str(stage / "stdout.log"), "stderr": str(stage / "stderr.log"),
            "status": "starting", "returncode": None,
        }
        write_json(stage / "command.json", item)
        self.report["steps"].append(item)
        self.flush()
        start = time.monotonic()
        child = None
        try:
            with (stage / "stdout.log").open("wb") as stdout, (stage / "stderr.log").open("wb") as stderr:
                process = subprocess.Popen(item["argv"], cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                                           stdout=stdout, stderr=stderr, start_new_session=True, close_fds=True)
                child = {"process": process, "pgid": process.pid, "signals": [], "stage": name, "closed": False}
                self.owned.append(child)
                item.update({"pid": process.pid, "pgid": process.pid, "status": "running"})
                self.flush()
                while process.poll() is None:
                    if not cleanup and self.cancel_signal is not None:
                        item["status"] = "cancelled"
                        self.stop_owned(child)
                        break
                    if time.monotonic() - start >= allowed:
                        item["status"] = "timed_out"
                        self.stop_owned(child)
                        break
                    time.sleep(0.2)
                item["returncode"] = process.poll()
                if item["status"] == "running":
                    item["status"] = "passed" if process.returncode == 0 else "failed"
                if not child["closed"] and self.group_exists(child["pgid"]):
                    item["remaining_group_stopped"] = self.stop_owned(child)
                    if not item["remaining_group_stopped"]:
                        item["status"] = "cleanup_incomplete"
                    elif item["status"] == "passed":
                        item["status"] = "failed"
                        item["detail"] = "Command returned success but left owned group members; stopped them"
                if process.poll() is not None:
                    process.wait(timeout=0)
                    if not child["closed"] and not self.group_exists(child["pgid"]):
                        child["closed"] = True
        except OSError as error:
            item.update({"status": "failed", "detail": str(error)})
        finally:
            item.update({"finished_at": utc_now(), "elapsed_seconds": round(time.monotonic() - start, 3)})
            if child is not None:
                item["owned_group_signals"] = child["signals"]
            write_json(stage / "result.json", item)
            self.flush()
        if item["status"] != "passed":
            self.error(name, item.get("detail", f"{item['status']}, exit {item['returncode']}"))
            if check:
                if item["status"] == "cancelled":
                    raise BatchStopped("Cancellation requested")
                raise StageFailure(f"{name}: {item['status']}")
        return item

    def json_command(self, name: str, command: list[str], cwd: Path, timeout: float = 60,
                     *, cleanup: bool = False) -> Any:
        item = self.run(name, command, cwd, timeout, cleanup=cleanup)
        try:
            return json.loads(Path(item["stdout"]).read_text())
        except (ValueError, OSError) as error:
            raise StageFailure(f"{name}: expected complete JSON output: {error}")

    def attempt(self, label: str, function) -> bool:
        self.checkpoint()
        try:
            function()
            return True
        except StageFailure as error:
            self.error(label, str(error))
            return False

    def snapshot(self, root: Path) -> dict[str, str]:
        result: dict[str, str] = {}
        for folder, directories, filenames in os.walk(root, followlinks=False):
            self.checkpoint()
            directories[:] = sorted(d for d in directories if d not in EXCLUDED_DIRS and not (Path(folder) / d).is_symlink())
            for filename in sorted(filenames):
                path = Path(folder) / filename
                if not path.is_symlink() and (path.suffix in SOURCE_SUFFIXES or filename == "Package.resolved"):
                    result[str(path.relative_to(root))] = digest(path)
        return result

    def validate_manifest(self, label: str) -> None:
        """Recheck every frozen input, retaining a distinct receipt at each boundary."""
        self.checkpoint()
        checks = self.report.setdefault("source_manifest_checks", [])
        sequence = len(checks) + 1
        safe_label = re.sub(r"[^A-Za-z0-9_-]", "-", label)
        receipt = self.output / "source-manifest-checks" / f"{sequence:03d}-{safe_label}.json"
        path = self.args.source_manifest
        record = {"sequence": sequence, "label": label, "started_at": utc_now(),
                  "manifest": str(path) if path is not None else None,
                  "receipt": str(receipt), "status": "running"}
        checks.append(record)
        checked: list[dict[str, Any]] = []
        mismatches: list[str] = []
        try:
            if path is None:
                raise StageFailure("An explicit frozen source manifest is required before native QA")
            payload = path.read_bytes()
            manifest_sha = hashlib.sha256(payload).hexdigest()
            record["manifest_sha256"] = manifest_sha
            frozen_sha = self.report.setdefault("source_manifest_sha256", manifest_sha)
            if manifest_sha != frozen_sha:
                raise StageFailure("Source manifest itself changed during the batch; baseline cannot be replaced")
            def unique_object(pairs):
                value = {}
                for key, item in pairs:
                    if key in value:
                        raise StageFailure(f"Duplicate source-manifest key/path: {key}")
                    value[key] = item
                return value

            value = json.loads(payload, object_pairs_hook=unique_object)
            if (not isinstance(value, dict) or type(value.get("schema_version")) is not int
                    or value["schema_version"] != 2):
                raise StageFailure("A complete schema_version 2 source manifest is required")
            policy = value.get("inventory_policy")
            if (not isinstance(policy, dict) or policy.get("follow_symlinks") is not False
                    or policy != inventory_policy()):
                raise StageFailure("Source-manifest inventory policy does not match this runner")
            if "files" in value:
                raise StageFailure("Schema 2 uses per-root files and optional additional_files")
            required_roots = {key: Path(getattr(self.args, key + "_root")).expanduser().resolve()
                              for key in self.args.apps}
            if self.args.advertising_preparation_root is not None:
                required_roots["advertising-preparation"] = self.args.advertising_preparation_root.expanduser().resolve()
            declarations = value.get("roots")
            if not isinstance(declarations, list) or len(declarations) != len(required_roots):
                raise StageFailure("Source manifest must declare every selected app/ad-kit root exactly once")
            declared: dict[str, dict[str, Any]] = {}
            paths: list[Path] = []
            for declaration in declarations:
                if not isinstance(declaration, dict):
                    raise StageFailure("Malformed source-manifest root declaration")
                key, path_text = declaration.get("key"), declaration.get("path")
                if (not isinstance(key, str) or key not in required_roots or key in declared
                        or not isinstance(path_text, str)):
                    raise StageFailure("Unexpected, missing or duplicate source-manifest root")
                source_root = Path(path_text)
                if (not source_root.is_absolute() or str(source_root.resolve()) != path_text
                        or source_root != required_roots[key] or not source_root.is_dir()):
                    raise StageFailure(f"Source-manifest root is missing, noncanonical or incorrect: {path_text}")
                if any(source_root == other or source_root in other.parents or other in source_root.parents
                       for other in paths):
                    raise StageFailure("Source-manifest roots must be distinct and nonoverlapping")
                files = declaration.get("files")
                if not isinstance(files, dict) or not files:
                    raise StageFailure(f"Source-manifest root lacks a complete nonempty inventory: {key}")
                paths.append(source_root)
                declared[key] = declaration
            if set(declared) != set(required_roots):
                raise StageFailure("Source-manifest root coverage is incomplete")
            additional = value.get("additional_files", {})
            if not isinstance(additional, dict):
                raise StageFailure("additional_files must map absolute paths to SHA-256 hashes")
            record["expected_file_count"] = sum(len(item["files"]) for item in declared.values()) + len(additional)
            record["roots"] = []
            seen_paths: set[str] = set()

            def checked_hash(expected: Any, source: Path) -> str:
                if not isinstance(expected, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
                    raise StageFailure(f"Invalid expected SHA-256 for {source}")
                if str(source) in seen_paths:
                    raise StageFailure(f"Duplicate source-manifest path: {source}")
                seen_paths.add(str(source))
                return expected.lower()

            for key, declaration in declared.items():
                self.checkpoint()
                source_root = required_roots[key]
                expected_files = {}
                for relative, expected in declaration["files"].items():
                    if not isinstance(relative, str):
                        raise StageFailure(f"Malformed relative input path in {key}")
                    relative_path = Path(relative)
                    if (not relative or relative_path.is_absolute() or str(relative_path) != relative
                            or ".." in relative_path.parts or "\\" in relative
                            or not (relative_path.suffix in SOURCE_SUFFIXES or relative_path.name == "Package.resolved")
                            or any(part in EXCLUDED_DIRS for part in relative_path.parts[:-1])):
                        raise StageFailure(f"Input path is noncanonical or outside the declared inventory policy: {relative}")
                    expected_files[relative] = checked_hash(expected, source_root / relative_path)
                actual_files = self.snapshot(source_root)
                added = sorted(set(actual_files) - set(expected_files))
                removed = sorted(set(expected_files) - set(actual_files))
                changed = sorted(name for name in set(actual_files) & set(expected_files)
                                 if actual_files[name] != expected_files[name])
                record["roots"].append({"key": key, "path": str(source_root),
                                        "expected_count": len(expected_files), "actual_count": len(actual_files),
                                        "added": added, "removed": removed, "changed": changed})
                for relative in sorted(set(expected_files) | set(actual_files)):
                    item = {"path": str(source_root / relative), "root": key,
                            "expected": expected_files.get(relative), "actual": actual_files.get(relative),
                            "matches": relative in expected_files and relative in actual_files
                            and expected_files[relative] == actual_files[relative]}
                    checked.append(item)
                    if not item["matches"]:
                        mismatches.append(item["path"])
            for path_text, expected in additional.items():
                self.checkpoint()
                source = Path(path_text)
                if (not source.is_absolute() or str(source.resolve()) != path_text
                        or any(source == root or root in source.parents for root in paths)):
                    raise StageFailure(f"Additional input must be canonical and outside declared roots: {path_text}")
                item = {"path": str(source), "expected": checked_hash(expected, source)}
                try:
                    item["actual"] = digest(source)
                except OSError as error:
                    item.update({"actual": None, "read_error": str(error)})
                item["matches"] = item["actual"] == item["expected"]
                checked.append(item)
                if not item["matches"]:
                    mismatches.append(str(source))
            if mismatches:
                raise StageFailure("Source manifest mismatch: " + ", ".join(mismatches))
            record["status"] = "passed"
        except BatchStopped as error:
            record.update({"status": "interrupted", "error": str(error)})
            raise
        except StageFailure as error:
            record.update({"status": "failed", "error": str(error)})
            raise
        except (OSError, ValueError, TypeError, KeyError) as error:
            record.update({"status": "failed", "error": str(error)})
            raise StageFailure(f"Source manifest validation failed: {error}") from error
        finally:
            record.update({"finished_at": utc_now(), "checked_file_count": len(checked),
                           "mismatch_count": len(mismatches)})
            self.report["source_manifest_status"] = record["status"]
            write_json(receipt, {**record, "files": checked})
            self.flush()

    def xcode_base(self, spec: dict[str, Any], lane: str, destination: str) -> list[str]:
        derived = self.output / "derived" / f"{spec['key']}-{lane}"
        return ["xcodebuild", "-project", str(spec["project"]), "-scheme", spec["scheme"],
                "-configuration", "Release", "-destination", destination,
                "-derivedDataPath", str(derived), "-disableAutomaticPackageResolution", "-skipPackageUpdates",
                "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]

    def validate_project(self, spec: dict[str, Any]) -> None:
        project_file = spec["project"] / "project.pbxproj"
        if not project_file.is_file():
            raise StageFailure(f"Missing project: {project_file}")
        if "XCRemoteSwiftPackageReference" in project_file.read_text():
            raise StageFailure("Remote Swift packages require a separate cached-dependency review; this runner never downloads packages")
        value = self.json_command(spec["key"] + "-list-project",
                                  ["xcodebuild", "-project", str(spec["project"]), "-list", "-json",
                                   "-disableAutomaticPackageResolution", "-skipPackageUpdates"], spec["root"], 90)
        project = value.get("project", {})
        if spec["scheme"] not in project.get("schemes", []):
            raise StageFailure(f"Expected scheme {spec['scheme']!r} was not listed; no guessed scheme selected")
        if spec["key"] == "lumina" and not {"LuminaTests", "LuminaUITests"}.issubset(set(project.get("targets", []))):
            raise StageFailure("Lumina unit/UI targets were not both listed")
        write_json(self.output / spec["key"] / "project-list.json", value)

    def swift_check(self, name: str, root: Path, sources: list[str], arguments: list[str] | None = None) -> None:
        cache = self.output / "fixtures" / name
        cache.mkdir(parents=True)
        for source in sources:
            if not (root / source).is_file():
                raise StageFailure(f"Missing fixture input: {root / source}")
        executable = cache / "check"
        self.run(name + "-compile", ["xcrun", "swiftc", "-Onone", "-module-cache-path", str(cache / "module-cache"),
                                    *sources, "-o", str(executable)], root, 180)
        self.run(name + "-run", [str(executable), *(arguments or [])], root, 180)

    def native_build(self, spec: dict[str, Any]) -> None:
        key = spec["key"]
        if self.args.skip_production:
            self.run(key + "-simulator-build",
                     self.xcode_base(spec, "simulator", "generic/platform=iOS Simulator")
                     + ["-resultBundlePath", str(self.output / key / "SimulatorBuild.xcresult"), "build"],
                     spec["root"], 720)
            return
        self.production_archive(spec)

    def advertising_checks(self) -> None:
        root = self.args.advertising_preparation_root.expanduser().resolve()
        policy = root / "Shared" / "AdvertisingPreparationPolicy.swift"
        preview = root / "Shared" / "LocalAdvertisingPreview.swift"
        script = root / "Tests" / "run-policy-checks.sh"
        if not all(path.is_file() for path in [policy, preview, script]):
            raise StageFailure("Advertising preparation inputs are missing")
        before = self.snapshot(root)
        self.run("advertising-offline-policy-checks", ["bash", str(script)], root, 240)
        sdk_step = self.run("advertising-simulator-sdk", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], root, 30)
        sdk = Path(Path(sdk_step["stdout"]).read_text().strip())
        if not sdk.is_dir():
            raise StageFailure("Installed simulator SDK could not be verified")
        self.run("advertising-local-preview-typecheck", ["xcrun", "swiftc", "-typecheck", "-swift-version", "5",
                 "-target", "arm64-apple-ios16.0-simulator", "-sdk", str(sdk),
                 "-module-cache-path", str(self.output / "advertising-module-cache"),
                 "-D", "DEBUG", "-D", "AD_PREPARATION_PREVIEW", str(policy), str(preview)], root, 180)
        if before != self.snapshot(root):
            raise StageFailure("Advertising preparation inputs changed during validation")

    def production_archive(self, spec: dict[str, Any]) -> None:
        key = spec["key"]
        folder = self.output / key
        folder.mkdir(exist_ok=True)
        archive = folder / "Production.xcarchive"
        base = self.xcode_base(spec, "production", "generic/platform=iOS")
        settings = self.json_command(key + "-production-settings", base + ["-showBuildSettings", "-json"], spec["root"], 90)
        if not isinstance(settings, list) or not settings:
            raise StageFailure("Production build settings are empty or malformed")
        app_settings = []
        for target in settings:
            build = target.get("buildSettings", {})
            for flag in ["SWIFT_ACTIVE_COMPILATION_CONDITIONS", "OTHER_SWIFT_FLAGS"]:
                if "UI_TESTING" in str(build.get(flag, "")):
                    raise StageFailure(f"Production settings contain UI_TESTING in {flag}; archive blocked")
            if build.get("WRAPPER_EXTENSION") == "app" and build.get("PRODUCT_TYPE") == "com.apple.product-type.application":
                app_settings.append(build)
        if len(app_settings) != 1:
            raise StageFailure("Cannot identify exactly one app target in production settings")
        settings_path = folder / "production-settings.json"
        write_json(settings_path, settings)
        self.run(key + "-production-archive", base + ["-archivePath", str(archive), "-resultBundlePath",
                 str(folder / "ProductionArchive.xcresult"), "archive"], spec["root"], 900)
        apps = list((archive / "Products" / "Applications").glob("*.app"))
        if len(apps) != 1:
            raise StageFailure("Archive does not contain exactly one application")
        app = apps[0]
        with (app / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        expected_bundle = app_settings[0].get("PRODUCT_BUNDLE_IDENTIFIER")
        if not expected_bundle or info.get("CFBundleIdentifier") != expected_bundle:
            raise StageFailure("Archived bundle identity does not match production settings")
        primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
        if not primary.get("CFBundleIconName") and not primary.get("CFBundleIconFiles"):
            raise StageFailure("Archived app has no populated primary icon metadata")
        if not (app / "Assets.car").is_file() or (app / "Assets.car").stat().st_size == 0:
            raise StageFailure("Archived app lacks a nonempty compiled asset catalogue")
        package = {
            "archive": str(archive), "app": str(app), "bundle_id": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
            "primary_icon": primary, "assets_bytes": (app / "Assets.car").stat().st_size,
            "code_signature_present": (app / "_CodeSignature").exists(),
            "embedded_profile_present": (app / "embedded.mobileprovision").exists(),
            "scope": "Local unsigned archive; not distribution signing or App Store acceptance",
        }
        write_json(folder / "archive-package.json", package)
        if package["code_signature_present"] or package["embedded_profile_present"]:
            raise StageFailure("Unsigned archive unexpectedly contains signing material; manual review required")
        if key == "lumina":
            verifier = spec["root"] / "ci_scripts" / "verify_release_archive.py"
            if not verifier.is_file():
                raise StageFailure(f"Required existing archive verifier is missing: {verifier}")
            self.run("lumina-release-archive-verifier", [sys.executable, str(verifier), str(archive), str(settings_path)],
                     spec["root"], 120)

    @staticmethod
    def device_rows(value: Any) -> list[tuple[str, dict[str, Any]]]:
        return [(runtime, device) for runtime, devices in value.get("devices", {}).items() for device in devices]

    def create_simulator(self, root: Path) -> str:
        types = self.json_command("simulator-types", ["xcrun", "simctl", "list", "devicetypes", "--json"], root)
        runtimes = self.json_command("simulator-runtimes", ["xcrun", "simctl", "list", "runtimes", "--json"], root)
        normalize = lambda value: re.sub(r"[^a-z0-9]", "", value.lower())
        selected = [entry for entry in types.get("devicetypes", []) if normalize(entry.get("name", "")) == normalize(self.args.sim_device_name)]
        runtime = [entry for entry in runtimes.get("runtimes", []) if entry.get("identifier") == self.args.sim_runtime_id and entry.get("isAvailable") is True]
        if len(selected) != 1 or len(runtime) != 1:
            raise StageFailure("Requested installed iPhone type/iOS runtime unavailable or ambiguous; no downloads or fallback")
        before = self.json_command("simulator-before", ["xcrun", "simctl", "list", "devices", "--json"], root)
        rows = self.device_rows(before)
        self.preexisting_devices = {device["udid"] for _, device in rows}
        if any(device.get("name") == self.simulator_name for _, device in rows):
            raise StageFailure("Unique simulator name already exists; refusing reuse")
        self.simulator_discovery_known = True
        self.simulator_create_attempted = True
        result = self.run("simulator-create", ["xcrun", "simctl", "create", self.simulator_name,
                          selected[0]["identifier"], self.args.sim_runtime_id], root, 60)
        text = Path(result["stdout"]).read_text().strip()
        try:
            identifier = str(uuid.UUID(text)).upper()
        except ValueError:
            raise StageFailure("New simulator ID could not be read; cleanup will reconcile the unique creation name")
        if identifier in self.preexisting_devices:
            raise StageFailure("simctl returned a pre-existing device; refusing ownership")
        self.simulator = identifier
        self.report["simulator"] = {"udid": identifier, "name": self.simulator_name,
                                    "runtime": self.args.sim_runtime_id, "created_by_this_run": True}
        self.flush()
        after = self.json_command("simulator-created-identity", ["xcrun", "simctl", "list", "devices", "--json"], root)
        matches = [(runtime_id, device) for runtime_id, device in self.device_rows(after) if device.get("udid") == identifier]
        if len(matches) != 1 or matches[0][0] != self.args.sim_runtime_id or matches[0][1].get("name") != self.simulator_name:
            self.simulator = None
            raise StageFailure("Created simulator identity verification failed; no boot attempted")
        self.simulator_boot_attempted = True
        self.run("simulator-boot", ["xcrun", "simctl", "boot", identifier], root, 90)
        self.run("simulator-bootstatus", ["xcrun", "simctl", "bootstatus", identifier, "-b"], root, 180)
        return identifier

    def lumina_tests(self, spec: dict[str, Any]) -> None:
        validate_lumina_test_sources(spec["root"])
        ci_guards = validate_lumina_ci_sources(spec["root"], spec["scheme"])
        folder = self.output / "lumina"
        folder.mkdir(exist_ok=True)
        ci_guards["actual_build_settings"] = {}
        for configuration, destination in [("Release", "generic/platform=iOS"), ("UIQA", "generic/platform=iOS Simulator")]:
            settings_command = self.xcode_base(spec, "ci-settings-" + configuration.lower(), destination)
            settings_command[settings_command.index("-configuration") + 1] = configuration
            settings = self.json_command("lumina-ci-settings-" + configuration.lower(),
                                         settings_command + ["-showBuildSettings", "-json"], spec["root"], 90)
            ci_guards["actual_build_settings"][configuration] = validate_lumina_ci_build_settings(settings, configuration)
        write_json(folder / "ci-configuration-guards.json", ci_guards)
        self.report["lumina_ci_configuration"] = ci_guards
        self.flush()
        identifier = self.create_simulator(spec["root"])
        result_bundle = folder / "UIQATests.xcresult"
        command = self.xcode_base(spec, "uiqa", "platform=iOS Simulator,id=" + identifier)
        command[command.index("-configuration") + 1] = "UIQA"
        command += ["-testPlan", "Lumina AI personal trainer", "-resultBundlePath", str(result_bundle),
                    "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1", "test"]
        result = self.run("lumina-uiqa-unit-ui-tests", command, spec["root"], 1200, check=False)
        if result_bundle.is_dir():
            summary = self.json_command("lumina-test-result-summary",
                                       ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)],
                                       spec["root"], 60)
            write_json(folder / "test-summary.json", summary)
            tree = self.json_command("lumina-test-result-tree",
                                    ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result_bundle)],
                                    spec["root"], 60)
            write_json(folder / "test-tree.json", tree)
            verified = validate_lumina_test_evidence(summary, tree, expected_device_id=identifier)
            write_json(folder / "verified-test-inventory.json", verified)
            self.report["lumina_test_inventory"] = verified
            self.report["lumina_test_counts"] = {key: summary.get(key) for key in ["totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"]}
            self.flush()
        else:
            raise StageFailure("No Lumina result bundle produced")
        if result["status"] != "passed":
            raise StageFailure("Lumina xcodebuild tests did not pass; result evidence retained")

    def cleanup_simulator(self) -> bool:
        if not self.simulator_create_attempted:
            return True
        try:
            value = self.json_command("cleanup-simulator-list", ["xcrun", "simctl", "list", "devices", "--json"],
                                      self.output, 20, cleanup=True)
            matches = [(runtime, device) for runtime, device in self.device_rows(value)
                       if device.get("name") == self.simulator_name and device.get("udid") not in self.preexisting_devices
                       and runtime == self.args.sim_runtime_id]
            if not self.simulator_discovery_known:
                return False
            if not matches and self.simulator is None and not self.simulator_boot_attempted:
                return True
            if len(matches) != 1 or (self.simulator is not None and matches[0][1].get("udid") != self.simulator):
                self.error("cleanup", "Cannot verify exactly one newly-created owned simulator; no device touched")
                return False
            device = matches[0][1]
            identifier = device["udid"]
            self.simulator = identifier
            if device.get("state") != "Shutdown":
                self.run("cleanup-own-simulator-shutdown", ["xcrun", "simctl", "shutdown", identifier],
                         self.output, 60, cleanup=True)
            verified = self.json_command("cleanup-simulator-verify", ["xcrun", "simctl", "list", "devices", "--json"],
                                         self.output, 20, cleanup=True)
            state = [device for runtime, device in self.device_rows(verified)
                     if runtime == self.args.sim_runtime_id and device.get("udid") == identifier
                     and device.get("name") == self.simulator_name]
            safe = len(state) == 1 and state[0].get("state") == "Shutdown"
            self.report["simulator_cleanup"] = {"udid": identifier, "shutdown_verified": safe,
                                                 "deleted": False, "other_devices_touched": False}
            return safe
        except Exception as error:
            self.error("cleanup-simulator", str(error))
            return False

    def cleanup(self) -> bool:
        groups_safe = True
        for child in self.owned:
            if not child["closed"]:
                groups_safe = self.stop_owned(child) and groups_safe
        simulator_safe = self.cleanup_simulator() if self.lock.acquired else True
        for child in self.owned:
            if not child["closed"]:
                groups_safe = False
        if self.lock.acquired and groups_safe and simulator_safe:
            released, detail = self.lock.release()
            self.report["lock"] = "released" if released else "retained"
            self.report["lock_cleanup_detail"] = detail
            if not released:
                self.error("cleanup-lock", detail)
            return released
        if self.lock.acquired:
            self.report["lock"] = "retained"
            self.error("cleanup", "Owned child groups or owned simulator could not be verified stopped; lock retained")
            return False
        return True


def specs_for(args: argparse.Namespace) -> dict[str, dict[str, Any]]:
    specs = {
        "halal": {"key": "halal", "root": args.halal_root, "project_name": "HalalAnalyzer حلال ام حرام؟.xcodeproj", "scheme": args.halal_scheme},
        "career": {"key": "career", "root": args.career_root, "project_name": "AhmadCareer.xcodeproj", "scheme": args.career_scheme},
        "lumina": {"key": "lumina", "root": args.lumina_root, "project_name": "Lumina.xcodeproj", "scheme": args.lumina_scheme},
    }
    for spec in specs.values():
        spec["root"] = spec["root"].expanduser().resolve()
        spec["project"] = spec["root"] / spec["project_name"]
    return specs


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot-authorized", required=True, help="Non-secret identifier of an acknowledged scheduling gap; no automatic waiting/retry")
    parser.add_argument("--apps", nargs="+", choices=["halal", "career", "lumina"], default=["halal", "career", "lumina"])
    parser.add_argument("--skip-production", action="store_true", help="Use Career/Halal simulator builds; omit Lumina production archive/verifier")
    parser.add_argument("--deadline-minutes", type=int, default=45, help="Total batch budget, including a two-minute cleanup reserve; 5–45")
    parser.add_argument("--source-manifest", type=Path)
    parser.add_argument("--advertising-preparation-root", type=Path, help="Optional isolated, no-network preparation kit; no SDK or app integration")
    parser.add_argument("--output-root", type=Path, default=Path("/Users/saleh/Library/Caches/Codex-PublishingQA"))
    parser.add_argument("--halal-root", type=Path, default=Path("/Users/saleh/Documents/HalalAnalyzer حلال ام حرام؟"))
    parser.add_argument("--career-root", type=Path, default=Path("/Users/saleh/Documents/Codex/2026-10-08/https-www-linkedin-com-in-ahmad-2/work/ahmad-career-github/apple"))
    parser.add_argument("--lumina-root", type=Path, default=Path("/Users/saleh/Documents/Codex/2026-11-02/riyadh-ai-jobs/work/app-store-release/sources/Lumina"))
    parser.add_argument("--halal-scheme", default="HalalAnalyzer حلال ام حرام؟")
    parser.add_argument("--career-scheme", default="AhmadCareer")
    parser.add_argument("--lumina-scheme", default="Lumina AI personal trainer")
    parser.add_argument("--sim-runtime-id", default="com.apple.CoreSimulator.SimRuntime.iOS-27-0")
    parser.add_argument("--sim-device-name", default="iPhone 18 Pro")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}", args.slot_authorized):
        parser.error("--slot-authorized must be an explicit 8–128 character non-secret scheduling identifier")
    if not 5 <= args.deadline_minutes <= 45:
        parser.error("--deadline-minutes must be between 5 and 45")
    if len(args.apps) != len(set(args.apps)):
        parser.error("An app may be selected only once in a serial batch")
    return args


def main() -> int:
    args = arguments()
    if sys.platform != "darwin":
        print("This runner is authored for the authorized Mac. No execution or lock action is performed here.", file=sys.stderr)
        return 2
    specs = specs_for(args)
    output_root = args.output_root.expanduser().resolve()
    for spec in specs.values():
        if output_root == spec["root"] or spec["root"] in output_root.parents:
            print("Output root must be outside all source checkouts", file=sys.stderr)
            return 2
    if output_root == LOCK_PATH or LOCK_PATH in output_root.parents:
        print("Output root must not be the shared lock", file=sys.stderr)
        return 2
    runner = Runner(args)
    previous_handlers = {}
    def request_stop(number, _frame):
        if runner.cancel_signal is None:
            runner.cancel_signal = number
    for number in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]:
        previous_handlers[number] = signal.signal(number, request_stop)
    exit_code = 0
    try:
        runner.checkpoint()
        runner.lock.acquire()
        runner.report["lock"] = "acquired"
        runner.report["lock_owner"] = runner.lock.record
        runner.report["free_output_disk_bytes"] = shutil.disk_usage(runner.output).free
        runner.flush()
        runner.validate_manifest("batch-start")
        if args.advertising_preparation_root is not None:
            ads_passed = runner.attempt("advertising-preparation", runner.advertising_checks)
            runner.report["advertising_preparation"] = {"status": "passed" if ads_passed else "failed",
                "scope": "Offline policy fixtures and local SwiftUI placeholder typecheck only",
                "app_integration": False, "advertising_sdk": False, "ad_requests": False,
                "preview_rendered": False}
            runner.flush()
        runner.run("xcode-version", ["xcodebuild", "-version"], runner.output, 30)
        runner.run("swift-version", ["xcrun", "swiftc", "--version"], runner.output, 30)
        for app in args.apps:
            runner.checkpoint()
            spec = specs[app]
            runner.validate_manifest("before-" + app)
            runner.report["app_results"][app] = {"status": "running", "source_hashes_unchanged": None}
            runner.flush()
            if not spec["root"].is_dir():
                runner.error(app, "Source root missing: " + str(spec["root"]))
                runner.report["app_results"][app] = {"status": "failed", "reason": "source root missing"}
                continue
            before = runner.snapshot(spec["root"])
            write_json(runner.output / app / "source-before.json", before)
            passed = runner.attempt(app + "-project-validation", lambda spec=spec: runner.validate_project(spec))
            if passed:
                if app == "halal":
                    passed = runner.attempt("halal-offline-regressions", lambda: runner.swift_check(
                        "halal-ingredients", spec["root"], ["HalalAnalyzer حلال ام حرام؟/IngredientScreening.swift", "Tests/main.swift"])) and passed
                    passed = runner.attempt("halal-native-build", lambda: runner.native_build(spec)) and passed
                elif app == "career":
                    passed = runner.attempt("career-offline-policy", lambda: runner.swift_check(
                        "career-policy", spec["root"], ["AhmadCareer/CareerPolicy.swift", "AhmadCareer/CareerFeed.swift", "Checks/main.swift"])) and passed
                    passed = runner.attempt("career-offline-store", lambda: runner.swift_check(
                        "career-store", spec["root"], ["AhmadCareer/CareerFeed.swift", "AhmadCareer/NativeCareerStore.swift", "Checks/NativeStoreCheck.swift"],
                        ["AhmadCareer/CareerResearch.json"])) and passed
                    passed = runner.attempt("career-native-build", lambda: runner.native_build(spec)) and passed
                else:
                    passed = runner.attempt("lumina-uiqa-tests", lambda: runner.lumina_tests(spec)) and passed
                    if not args.skip_production:
                        passed = runner.attempt("lumina-production-archive", lambda: runner.production_archive(spec)) and passed
            after = runner.snapshot(spec["root"])
            write_json(runner.output / app / "source-after.json", after)
            changed = sorted(path for path in set(before) | set(after) if before.get(path) != after.get(path))
            if changed:
                runner.error(app + "-source-stability", "Input files changed during QA: " + ", ".join(changed))
                passed = False
            runner.report["app_results"][app] = {"status": "passed" if passed else "failed", "source_hashes_unchanged": not changed,
                                                   "changed_inputs": changed, "production_included": not args.skip_production}
            runner.flush()
        runner.validate_manifest("after-apps")
    except Occupied as error:
        runner.report["lock"] = "occupied"
        runner.error("lock", str(error))
        exit_code = 75
    except BatchStopped as error:
        runner.error("batch", str(error))
        exit_code = 128 + runner.cancel_signal if runner.cancel_signal is not None else 124
    except Exception as error:
        runner.error("batch", f"{type(error).__name__}: {error}")
        exit_code = 2
    finally:
        try:
            cleanup_safe = runner.cleanup()
        except Exception as error:
            # Fail closed; never remove the shared lock after uncertain cleanup.
            cleanup_safe = False
            runner.report["lock"] = "retained" if runner.lock.acquired else runner.report["lock"]
            runner.report["errors"].append({"stage": "cleanup", "message": f"{type(error).__name__}: {error}", "at": utc_now()})
        if not cleanup_safe and exit_code == 0:
            exit_code = 1
        if runner.report["errors"] and exit_code == 0:
            exit_code = 1
        for app in args.apps:
            runner.report["app_results"].setdefault(app, {"status": "not run"})
            if runner.report["app_results"][app]["status"] == "running":
                runner.report["app_results"][app]["status"] = "interrupted"
        runner.report.update({"finished_at": utc_now(), "elapsed_seconds": round(time.monotonic() - runner.started, 3),
                              "exit_code": exit_code, "cleanup_safe": cleanup_safe})
        runner.flush()
        for number, handler in previous_handlers.items():
            signal.signal(number, handler)
        print(json.dumps({"report": str(runner.output / "report.json"), "exit_code": exit_code,
                          "lock": runner.report["lock"], "app_results": runner.report["app_results"]}, ensure_ascii=False))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
