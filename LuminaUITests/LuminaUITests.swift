import XCTest
import Foundation
import UIKit
import Vision

final class LuminaUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testNavigationAndDataControlCancelPaths() throws {
        let app = launchQAApplication()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Offline Home"
        home.lifetime = .keepAlways
        add(home)

        for (tab, heading) in [("Workouts", "Log Workout"), ("Nutrition", "Log Meal")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.staticTexts[heading].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Offline coaching"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        app.buttons["lumina.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.buttons["Apple Health information"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["Health access is unavailable in this build. Your existing records remain available."].exists)
        app.alerts.buttons["OK"].tap()

        app.buttons["Export database backup"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 30))
        if !app.buttons["Cancel"].exists, app.buttons["Browse"].exists {
            app.buttons["Browse"].tap()
        }
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 30))
        let exporter = XCTAttachment(screenshot: app.screenshot())
        exporter.name = "Database Export Picker"
        exporter.lifetime = .keepAlways
        add(exporter)
        app.buttons["Cancel"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Save"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)

        let deleteButton = app.buttons["Delete all local data"]
        if !deleteButton.isHittable { app.swipeUp() }
        deleteButton.tap()
        let title = app.staticTexts["Delete all local Lumina records and photos?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // The native popover omits Cancel on this OS; its outside margin dismisses safely.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        }
        let confirmationDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [confirmationDismissed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    @MainActor
    func testVeryLargeTextExpandsJournalRows() throws {
        let app = launchQAApplication()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Meals logged today:")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let normalHeight = row.frame.height
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        for _ in 0..<3 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.exists)
        print("DYNAMIC TYPE HEIGHTS:", normalHeight, row.frame.height)
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-large-text.png")
        try app.screenshot().pngRepresentation.write(to: imageURL)
        print("LARGE TEXT SCREENSHOT:", imageURL.path)
        XCTAssertGreaterThan(row.frame.height, normalHeight)
    }

    @MainActor
    func testHomeAccessibilityAudit() throws {
        let app = launchQAApplication()
        let home = app.navigationBars["Lumina"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        let titleMatches = home.staticTexts.matching(NSPredicate(format: "label == %@", "Lumina"))
        attachHomeAuditScreenshot(app, "Initial Home title state")
        attachHomeAuditJSON("Initial Home title", [
            "navigation_bar": homeAuditFrame(home.frame), "match_count": titleMatches.count,
            "title_matches": titleMatches.allElementsBoundByIndex.map(homeAuditElement),
        ])
        try requireHomeAudit(titleMatches.count == 1, "Initial Home title must resolve uniquely")
        let title = titleMatches.element(boundBy: 0)
        try requireHomeAudit(validHomeAuditFrame(home.frame) && validHomeAuditFrame(title.frame)
            && home.frame.contains(title.frame) && title.isHittable,
            "Initial Home title must be fully visible inside the navigation bar")

        let leaves = expectedHomeAuditLeaves()
        let ledger = HomeAuditLedger()
        try requireHomeAudit(leaves.count == 20 && Set(leaves.map(\.key)).count == 20,
            "Home contrast coverage must contain exactly 20 unique leaves")
        do {
            // Keep the original three viewport states, including their intervening swipes.
            for position in 0..<3 {
                try auditHomeContrast(app, leaves: leaves, ledger: ledger,
                    name: "Original position \(position)")
                app.swipeUp()
            }
            // A successful full audit credits every fully visible leaf at that pose.
            // Revisiting one debt can therefore settle several debts and missing leaves.
            for attempt in 0..<12 {
                let outstanding = leaves.filter {
                    ledger.pending.contains($0.key) || !ledger.covered.contains($0.key)
                }
                if outstanding.isEmpty { break }
                let targeted = try revealHomeAuditLeaves(outstanding, in: app,
                    leaves: leaves, ledger: ledger)
                try auditHomeContrast(app, leaves: leaves, ledger: ledger,
                    name: "Coverage pass \(attempt) for \(targeted.joined(separator: "; "))")
            }
            try requireHomeAudit(ledger.covered == Set(leaves.map(\.key)),
                "Missing fully visible contrast coverage: \(Set(leaves.map(\.key)).subtracting(ledger.covered).sorted())")
            try requireHomeAudit(ledger.pending.isEmpty,
                "Unresolved contrast findings: \(ledger.pending.sorted())")
            attachHomeAuditJSON("Home contrast coverage complete", ledger.summary)
            print("HOME CONTRAST COVERAGE: 20/20; unresolved findings: 0; full audits:", ledger.audits)
        } catch {
            attachHomeAuditJSON("Home contrast coverage FAILED", ledger.summary)
            attachHomeAuditScreenshot(app, "Home contrast failure state")
            throw error
        }
        // Dynamic Type audits resize the app; keep contrast checks in a separate pass.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast))
    }

    private struct HomeAuditLeaf {
        let isButton: Bool
        let label: String
        var key: String { (isButton ? "button:" : "text:") + label }
    }

    @MainActor
    private final class HomeAuditLedger {
        var covered: Set<String> = []
        var pending: Set<String> = []
        var audits = 0
        var findings: [[String: Any]] = []
        var movements: [[String: Any]] = []
        var observedFrames: [[String: CGRect]] = []
        var auditedFrames: [[String: CGRect]] = []
        var recoveryPlans: [[String: Any]] = []
        var actuationLoss: [String: CGFloat] = [:]
        var calibrationProvenance: [[String: Any]] = []
        var summary: [String: Any] {
            ["required_leaf_count": 20, "covered": covered.sorted(),
             "unresolved": pending.sorted(), "full_audit_count": audits,
             "findings": findings, "movements": movements,
             "observed_reachable_pose_count": observedFrames.count,
             "audited_pose_count": auditedFrames.count, "recovery_plans": recoveryPlans,
             "actuation_loss_points": actuationLoss.mapValues { String(describing: $0) },
             "calibration_provenance": calibrationProvenance]
        }
    }

    private func expectedHomeAuditLeaves() -> [HomeAuditLeaf] {
        let texts = [
            "Isolated QA store", "Your journal", "Offline coaching",
            "Check-in streak: 0 days", "Workouts logged today: 0", "Meals logged today: 0",
            "Health records", "No health records available.",
            "Lumina does not calculate readiness, recovery or nutrition scores. These records do not establish a habit's effects.",
            "Log and review",
            "Earlier prototype versions added sample records. Review existing entries before treating them as your own measurements.",
        ]
        let links = ["Log workout", "Log meal", "Daily check-in", "Offline coach",
                     "Progress photos", "Habits", "Goals", "Journal", "Training suggestions"]
        return texts.map { HomeAuditLeaf(isButton: false, label: $0) }
            + links.map { HomeAuditLeaf(isButton: true, label: $0) }
    }

    private func requireHomeAudit(_ condition: Bool, _ reason: String) throws {
        if !condition {
            throw NSError(domain: "LuminaHomeAudit", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    private func validHomeAuditFrame(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
    }

    private func homeAuditFrame(_ frame: CGRect) -> [String: String] {
        ["x": String(describing: frame.origin.x), "y": String(describing: frame.origin.y),
         "width": String(describing: frame.width), "height": String(describing: frame.height)]
    }

    @MainActor
    private func homeAuditElement(_ element: XCUIElement) -> [String: Any] {
        ["label": element.label, "identifier": element.identifier,
         "element_type": element.elementType.rawValue, "frame": homeAuditFrame(element.frame),
         "exists": element.exists, "hittable": element.isHittable]
    }

    @MainActor
    private func homeAuditViewport(_ app: XCUIApplication) throws -> CGRect {
        let bars = app.tabBars.allElementsBoundByIndex
        let navigation = app.navigationBars.matching(identifier: "Lumina").allElementsBoundByIndex
        let scrolls = app.scrollViews.allElementsBoundByIndex
        try requireHomeAudit(bars.count == 1 && navigation.count == 1 && scrolls.count == 1,
            "Home must have exactly one navigation bar, tab bar and scroll view")
        let window = app.frame
        let top = navigation[0].frame
        let bottom = bars[0].frame
        let scroll = scrolls[0].frame
        try requireHomeAudit([window, top, bottom, scroll].allSatisfy(validHomeAuditFrame),
            "Missing or invalid Home viewport geometry")
        try requireHomeAudit(window.intersects(top) && window.intersects(bottom)
            && top.maxY < bottom.minY, "System bars do not define an unobscured Home viewport")
        let viewport = CGRect(x: window.minX, y: max(window.minY, top.maxY),
            width: window.width, height: min(window.maxY, bottom.minY) - max(window.minY, top.maxY))
            .intersection(scroll)
        try requireHomeAudit(validHomeAuditFrame(viewport), "Empty Home audit viewport")
        return viewport
    }

    @MainActor
    private func resolveHomeAuditLeaf(_ leaf: HomeAuditLeaf, in app: XCUIApplication) throws -> XCUIElement {
        let scrolls = app.scrollViews.allElementsBoundByIndex
        try requireHomeAudit(scrolls.count == 1, "Home scroll identity is ambiguous")
        let query = leaf.isButton ? scrolls[0].buttons : scrolls[0].staticTexts
        let matches = query.matching(NSPredicate(format: "label == %@", leaf.label))
            .allElementsBoundByIndex
        try requireHomeAudit(matches.count == 1, "Home leaf must resolve uniquely: \(leaf.key)")
        let element = matches[0]
        try requireHomeAudit(element.exists && validHomeAuditFrame(element.frame),
            "Missing or invalid Home leaf: \(leaf.key)")
        return element
    }

    private func homeAuditDeferralGeometry(_ frame: CGRect, viewport: CGRect, window: CGRect) -> Bool {
        guard validHomeAuditFrame(frame), validHomeAuditFrame(viewport), validHomeAuditFrame(window),
              frame.minX >= viewport.minX, frame.maxX <= viewport.maxX,
              frame.width <= viewport.width, frame.height <= viewport.height,
              !viewport.contains(frame) else { return false }
        // A known leaf can be wholly above/below the viewport, even outside the window.
        // It still owes a later fully visible audit; isHittable alone never grants deferral.
        if frame.maxY <= viewport.minY || frame.minY >= viewport.maxY { return true }
        let topBand = CGRect(x: window.minX, y: window.minY, width: window.width,
                             height: max(0, viewport.minY - window.minY))
        let bottomBand = CGRect(x: window.minX, y: viewport.maxY, width: window.width,
                                height: max(0, window.maxY - viewport.maxY))
        return [topBand, bottomBand].contains { band in
            let intersection = frame.intersection(band)
            return !intersection.isNull && intersection.width > 0 && intersection.height > 0
        }
    }

    @MainActor
    private func auditHomeContrast(_ app: XCUIApplication, leaves: [HomeAuditLeaf],
                                   ledger: HomeAuditLedger, name: String) throws {
        let viewport = try homeAuditViewport(app)
        let window = app.frame
        var beforeFrames: [String: CGRect] = [:]
        var beforeIdentifiers: [String: String] = [:]
        var beforeRecords: [[String: Any]] = []
        var visibleBefore: Set<String> = []
        for leaf in leaves {
            let element = try resolveHomeAuditLeaf(leaf, in: app)
            beforeFrames[leaf.key] = element.frame
            beforeIdentifiers[leaf.key] = element.identifier
            var record = homeAuditElement(element)
            record["key"] = leaf.key
            record["fully_visible"] = viewport.contains(element.frame) && element.isHittable
            beforeRecords.append(record)
            if viewport.contains(element.frame) && element.isHittable { visibleBefore.insert(leaf.key) }
        }
        attachHomeAuditScreenshot(app, "Home contrast — \(name)")
        var passed = false
        var poseFindings: [[String: Any]] = []
        defer {
            attachHomeAuditJSON("Home contrast evidence — \(name)", [
                "name": name, "audit_passed": passed, "viewport": homeAuditFrame(viewport),
                "leaves_before": beforeRecords, "findings": poseFindings,
                "covered_after": ledger.covered.sorted(), "unresolved_after": ledger.pending.sorted(),
            ])
        }
        try app.performAccessibilityAudit(for: .contrast) { issue in
            var record: [String: Any] = ["pose": name, "description": issue.compactDescription,
                "detail": issue.detailedDescription, "decision": "FAIL"]
            defer { poseFindings.append(record); ledger.findings.append(record) }
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            record["element"] = self.homeAuditElement(element)
            let matching = leaves.filter {
                $0.label == element.label
                    && element.elementType == ($0.isButton ? .button : .staticText)
            }
            guard matching.count == 1, let leaf = matching.first,
                  let current = try? self.resolveHomeAuditLeaf(leaf, in: app),
                  current.identifier == element.identifier, current.frame == element.frame,
                  beforeIdentifiers[leaf.key] == element.identifier,
                  beforeFrames[leaf.key] == element.frame,
                  (try? self.homeAuditViewport(app)) == viewport,
                  self.homeAuditDeferralGeometry(element.frame, viewport: viewport, window: window)
            else { return false }
            // No issue is forgiven: every occurrence creates a debt to a later full audit.
            ledger.pending.insert(leaf.key)
            record["decision"] = "DEFER_REQUIRING_FULLY_VISIBLE_REAUDIT"
            record["key"] = leaf.key
            return true
        }
        try requireHomeAudit(try homeAuditViewport(app) == viewport && app.frame == window,
            "Home viewport changed during the contrast audit")
        for leaf in leaves {
            let element = try resolveHomeAuditLeaf(leaf, in: app)
            try requireHomeAudit(element.frame == beforeFrames[leaf.key]
                && element.identifier == beforeIdentifiers[leaf.key],
                "Home identity or frame changed during contrast audit: \(leaf.key)")
            if visibleBefore.contains(leaf.key) {
                try requireHomeAudit(viewport.contains(element.frame) && element.isHittable,
                    "Home leaf lost visibility during audit: \(leaf.key)")
                ledger.covered.insert(leaf.key)
                ledger.pending.remove(leaf.key)
            }
        }
        try requireVisibleHomeTitle(app, name: name)
        // Successful full audits establish actual reachable content positions.
        // Recording geometry grants no additional coverage or debt relief.
        ledger.observedFrames.append(beforeFrames)
        ledger.auditedFrames.append(beforeFrames)
        ledger.audits += 1
        passed = true
    }

    @MainActor
    private func requireVisibleHomeTitle(_ app: XCUIApplication, name: String) throws {
        let bars = app.navigationBars.matching(identifier: "Lumina")
        attachHomeAuditScreenshot(app, "Home title after contrast — \(name)")
        try requireHomeAudit(bars.count == 1, "Home title requires one navigation bar: \(name)")
        let bar = bars.element(boundBy: 0)
        let matches = bar.staticTexts.matching(NSPredicate(format: "label == %@", "Lumina"))
        attachHomeAuditJSON("Home title after contrast — \(name)", [
            "state": name, "navigation_bar": homeAuditFrame(bar.frame),
            "match_count": matches.count,
            "title_matches": matches.allElementsBoundByIndex.map(homeAuditElement),
        ])
        try requireHomeAudit(matches.count == 1, "Home title must remain unique: \(name)")
        let title = matches.element(boundBy: 0)
        try requireHomeAudit(validHomeAuditFrame(bar.frame) && validHomeAuditFrame(title.frame)
            && bar.frame.contains(title.frame) && title.isHittable,
            "Home title must remain fully visible inside the navigation bar: \(name)")
    }

    private func homeAuditBoundaryCrossings(_ frames: [String: CGRect],
                                           viewport: CGRect) -> [String] {
        frames.compactMap { key, frame -> String? in
            let crossesTop = frame.minY < viewport.minY && frame.maxY > viewport.minY
            let crossesBottom = frame.minY < viewport.maxY && frame.maxY > viewport.maxY
            return crossesTop || crossesBottom ? key : nil
        }.sorted()
    }

    private struct HomeAuditRecoveryPose {
        let shift: CGFloat
        let lower: CGFloat
        let upper: CGFloat
        let visibleOutstanding: Set<String>
        let visiblePending: Set<String>
    }

    private func homeAuditRecoveryPose(_ frames: [String: CGRect], outstanding: Set<String>,
                                      pending: Set<String>, viewport: CGRect,
                                      reachable: (lower: CGFloat, upper: CGFloat),
                                      auditedFrames: [[String: CGRect]]) throws -> HomeAuditRecoveryPose {
        try requireHomeAudit(validHomeAuditFrame(viewport) && frames.count == 20,
            "Recovery requires the measured viewport and all 20 Home leaves")
        try requireHomeAudit(!outstanding.isEmpty && outstanding.isSubset(of: Set(frames.keys))
            && pending.isSubset(of: Set(frames.keys)), "Unknown or empty recovery debt set")
        for frame in frames.values {
            try requireHomeAudit(validHomeAuditFrame(frame)
                && frame.minX >= viewport.minX && frame.maxX <= viewport.maxX
                && frame.width <= viewport.width && frame.height <= viewport.height,
                "A Home leaf cannot fit the measured recovery viewport")
        }
        try requireHomeAudit(reachable.lower.isFinite && reachable.upper.isFinite
            && reachable.lower <= 0 && reachable.upper >= 0,
            "Invalid observed recovery range")
        let lower = reachable.lower
        let upper = reachable.upper
        try requireHomeAudit(lower < upper, "No interior recovery range is available")
        guard let anchor = frames.keys.sorted().first else {
            throw NSError(domain: "LuminaHomeAudit", code: 1)
        }
        // Compare all20 leaf frames, not an approximate scroll offset or screenshot.
        // Excluding an already-audited visibility interval also prevents a fractional
        // midpoint from landing on the same pixel-rounded native pose again.
        let auditedShifts = try auditedFrames.map {
            try homeAuditCoherentTranslation(frames, after: $0, target: anchor)
        }
        var boundaries: Set<CGFloat> = [lower, upper]
        for frame in frames.values {
            for edge in [viewport.minY, viewport.maxY] {
                for shift in [edge - frame.minY, edge - frame.maxY]
                    where shift >= lower && shift <= upper {
                    boundaries.insert(shift)
                }
            }
        }
        let cuts = boundaries.sorted()
        var selected: HomeAuditRecoveryPose?
        for index in 0..<(cuts.count - 1) {
            let low = cuts[index]
            let high = cuts[index + 1]
            guard low < high,
                  !auditedShifts.contains(where: { low < $0 && $0 < high }) else { continue }
            let shift: CGFloat = low < 0 && 0 < high ? 0 : low + (high - low) / 2
            let moved = frames.mapValues { $0.offsetBy(dx: 0, dy: shift) }
            let visible = Set(moved.compactMap { viewport.contains($0.value) ? $0.key : nil })
            let visibleOutstanding = visible.intersection(outstanding)
            let visiblePending = visible.intersection(pending)
            guard !visibleOutstanding.isEmpty,
                  homeAuditBoundaryCrossings(moved, viewport: viewport).isEmpty else { continue }
            let candidate = HomeAuditRecoveryPose(shift: shift, lower: low, upper: high,
                visibleOutstanding: visibleOutstanding, visiblePending: visiblePending)
            // First cover the largest actual outstanding set. Prefer unresolved
            // findings over first-time coverage, then wider landing clearance.
            // Geometry selects a pose only; it never grants audit coverage or clears debt.
            if let current = selected {
                let better = candidate.visibleOutstanding.count > current.visibleOutstanding.count
                    || (candidate.visibleOutstanding.count == current.visibleOutstanding.count
                        && candidate.visiblePending.count > current.visiblePending.count)
                    || (candidate.visibleOutstanding.count == current.visibleOutstanding.count
                        && candidate.visiblePending.count == current.visiblePending.count
                        && high - low > current.upper - current.lower)
                    || (candidate.visibleOutstanding.count == current.visibleOutstanding.count
                        && candidate.visiblePending.count == current.visiblePending.count
                        && high - low == current.upper - current.lower
                        && abs(shift) < abs(current.shift))
                if better { selected = candidate }
            } else {
                selected = candidate
            }
        }
        guard let selected else {
            throw NSError(domain: "LuminaHomeAudit", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "No unaudited gap-aligned pose inside the observed scroll range can cover the outstanding leaves"])
        }
        return selected
    }

    @MainActor
    private func homeAuditRecoveryFrames(_ leaves: [HomeAuditLeaf],
                                         in app: XCUIApplication) throws -> [String: CGRect] {
        try requireHomeAudit(leaves.count == 20 && Set(leaves.map(\.key)).count == 20,
            "Recovery requires exactly 20 unique Home leaves")
        var frames: [String: CGRect] = [:]
        for leaf in leaves { frames[leaf.key] = try resolveHomeAuditLeaf(leaf, in: app).frame }
        return frames
    }

    private func homeAuditCoherentTranslation(_ before: [String: CGRect],
                                              after: [String: CGRect], target: String) throws -> CGFloat {
        try requireHomeAudit(before.count == 20 && Set(before.keys) == Set(after.keys),
            "Actuation calibration requires the same 20 Home leaves")
        guard let oldTarget = before[target], let newTarget = after[target] else {
            throw NSError(domain: "LuminaHomeAudit", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown actuation target: \(target)"])
        }
        let measured = newTarget.minY - oldTarget.minY
        try requireHomeAudit(measured.isFinite, "Nonfinite recovery translation")
        for (key, old) in before {
            guard let new = after[key] else { throw NSError(domain: "LuminaHomeAudit", code: 1) }
            let magnitudes: [CGFloat] = [1, abs(old.minY), abs(new.minY), abs(old.height), abs(new.height),
                                        abs(old.minX), abs(new.minX), abs(old.width), abs(new.width)]
            let arithmeticAllowance = CGFloat.ulpOfOne * (magnitudes.max() ?? 1) * 16
            // Floating-point arithmetic allowance only, many orders below a pixel.
            try requireHomeAudit(validHomeAuditFrame(old) && validHomeAuditFrame(new)
                && abs(new.minX - old.minX) <= arithmeticAllowance
                && abs(new.width - old.width) <= arithmeticAllowance
                && abs(new.height - old.height) <= arithmeticAllowance
                && abs((new.minY - old.minY) - measured) <= arithmeticAllowance,
                "Home leaves did not translate coherently: \(key)")
        }
        return measured
    }

    @MainActor
    private func homeAuditReachableRange(_ frames: [String: CGRect], target: String,
                                         ledger: HomeAuditLedger) throws -> (lower: CGFloat, upper: CGFloat) {
        try requireHomeAudit(ledger.observedFrames.count >= 3,
            "Recovery requires all three original audited poses")
        var lower: CGFloat = 0
        var upper: CGFloat = 0
        for observed in ledger.observedFrames {
            let shift = try homeAuditCoherentTranslation(frames, after: observed, target: target)
            lower = min(lower, shift)
            upper = max(upper, shift)
        }
        return (lower, upper)
    }

    @MainActor
    private func revealHomeAuditLeaves(_ outstanding: [HomeAuditLeaf], in app: XCUIApplication,
                                      leaves: [HomeAuditLeaf], ledger: HomeAuditLedger) throws -> [String] {
        let outstandingKeys = Set(outstanding.map(\.key))
        try requireHomeAudit(outstandingKeys.count == outstanding.count && !outstanding.isEmpty,
            "Recovery requires a nonempty unique outstanding set")
        guard let anchor = leaves.first else { throw NSError(domain: "LuminaHomeAudit", code: 1) }
        for gesture in 0..<10 {
            let viewport = try homeAuditViewport(app)
            let window = app.frame
            let frames = try homeAuditRecoveryFrames(leaves, in: app)
            let reachable = try homeAuditReachableRange(frames, target: anchor.key, ledger: ledger)
            let pose = try homeAuditRecoveryPose(frames, outstanding: outstandingKeys,
                pending: ledger.pending, viewport: viewport, reachable: reachable,
                auditedFrames: ledger.auditedFrames)
            guard let leaf = outstanding.first(where: { pose.visibleOutstanding.contains($0.key) }) else {
                throw NSError(domain: "LuminaHomeAudit", code: 1)
            }
            let element = try resolveHomeAuditLeaf(leaf, in: app)
            let frame = element.frame
            ledger.recoveryPlans.append([
                "gesture": gesture, "outstanding": outstandingKeys.sorted(),
                "pending": ledger.pending.sorted(), "selected_visible": pose.visibleOutstanding.sorted(),
                "selected_pending": pose.visiblePending.sorted(), "audited_pose_count": ledger.auditedFrames.count,
                "planned_content_shift": String(describing: pose.shift),
                "feasible_shift_lower": String(describing: pose.lower),
                "feasible_shift_upper": String(describing: pose.upper)])
            let plannedViewport = try homeAuditViewport(app)
            try requireHomeAudit(frames[leaf.key] == frame
                && plannedViewport == viewport && app.frame == window,
                "Home geometry changed while planning recovery")
            let crossing = homeAuditBoundaryCrossings(frames, viewport: viewport)
            if pose.shift == 0 {
                try requireHomeAudit(crossing.isEmpty, "Selected recovery pose crosses a viewport boundary")
                for target in outstanding where pose.visibleOutstanding.contains(target.key) {
                    let visible = try resolveHomeAuditLeaf(target, in: app)
                    try requireHomeAudit(viewport.contains(visible.frame) && visible.isHittable,
                        "Selected recovery target is not fully visible and hittable: \(target.key)")
                }
                return pose.visibleOutstanding.sorted()
            }
            try requireHomeAudit(!viewport.contains(frame) || element.isHittable,
                "Home leaf is geometrically visible but not hittable: \(leaf.key)")
            try requireHomeAudit(pose.shift.isFinite && pose.shift != 0,
                "Recovery cannot make measurable progress for: \(leaf.key)")
            // The interval and available range both come from actual geometry.
            // First measure a substantial drag in the requested direction, within
            // already reached content positions. Its purpose is calibration, not
            // landing or audit credit. Subsequent commands compensate only the
            // loss measured for this direction, then remeasure all actual frames.
            let direction: CGFloat = pose.shift > 0 ? 1 : -1
            let directionKey = direction > 0 ? "positive" : "negative"
            let available = direction > 0 ? reachable.upper : -reachable.lower
            let learnedLoss = ledger.actuationLoss[directionKey]
            let travel: CGFloat
            if let learnedLoss {
                try requireHomeAudit(learnedLoss.isFinite && learnedLoss >= 0,
                    "Invalid measured actuation loss")
                travel = min(abs(pose.shift) + learnedLoss, viewport.height * 0.45)
                try requireHomeAudit(travel > learnedLoss,
                    "No positive content travel remains within the gesture cap")
            } else {
                travel = min(available, viewport.height * 0.45)
                try requireHomeAudit(travel >= viewport.height * 0.25,
                    "Observed scroll range cannot support a substantial calibration drag")
            }
            try requireHomeAudit(travel.isFinite && travel > 0,
                "Invalid recovery finger travel")
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let start = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                dy: viewport.midY - window.minY - direction * travel / 2))
            let end = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                dy: viewport.midY - window.minY + direction * travel / 2))
            var movement: [String: Any] = ["target": leaf.key, "gesture": gesture,
                "viewport": homeAuditFrame(viewport), "element_before": homeAuditElement(element),
                "all_frames_before": frames.mapValues(homeAuditFrame),
                "boundary_crossings_before": crossing,
                "planned_content_shift": String(describing: pose.shift),
                "feasible_shift_lower": String(describing: pose.lower),
                "feasible_shift_upper": String(describing: pose.upper),
                "vertical_travel": String(describing: direction * travel),
                "gesture_velocity": "slow", "hold_after_drag_seconds": 0.25,
                "direction": directionKey,
                "calibration_mode": learnedLoss == nil ? "MEASURED_LARGE_PROBE" : "OBSERVED_LOSS_COMPENSATION",
                "observed_shift_lower": String(describing: reachable.lower),
                "observed_shift_upper": String(describing: reachable.upper),
                "previous_observed_loss": learnedLoss.map { String(describing: $0) } ?? "none",
                "predicted_content_travel": String(describing: direction * (travel - (learnedLoss ?? 0)))]
            defer { ledger.movements.append(movement) }
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.25)
            let afterViewport = try homeAuditViewport(app)
            let afterFrames = try homeAuditRecoveryFrames(leaves, in: app)
            let afterElement = try resolveHomeAuditLeaf(leaf, in: app)
            movement["all_frames_after"] = afterFrames.mapValues(homeAuditFrame)
            movement["raw_target_shift"] = String(describing: afterElement.frame.minY - frame.minY)
            let measured = try homeAuditCoherentTranslation(frames, after: afterFrames, target: leaf.key)
            movement["measured_content_shift"] = String(describing: measured)
            movement["boundary_crossings_after"] = homeAuditBoundaryCrossings(afterFrames,
                                                                               viewport: afterViewport)
            try requireHomeAudit(afterViewport == viewport && app.frame == window
                && afterFrames[leaf.key] == afterElement.frame,
                "Home viewport or target changed during recovery")
            try requireHomeAudit(measured.isFinite && measured * pose.shift > 0,
                "Recovery drag made no progress in the requested direction: \(leaf.key)")
            let loss = travel - abs(measured)
            movement["observed_actuation_loss"] = String(describing: loss)
            try requireHomeAudit(loss.isFinite && loss >= 0,
                "Recovery moved farther than its physical drag; do not calibrate an unexpected jump")
            try requireHomeAudit(measured >= reachable.lower && measured <= reachable.upper,
                "Recovery left its observed content range")
            if learnedLoss == nil {
                try requireHomeAudit(abs(measured) >= travel / 2,
                    "Recovery probe did not establish a usable actuation response")
                ledger.actuationLoss[directionKey] = loss
                ledger.calibrationProvenance.append([
                    "direction": directionKey, "target": leaf.key,
                    "movement_index": ledger.movements.count,
                    "gesture": gesture, "all20_frames_coherent": true,
                    "finger_travel": String(describing: direction * travel),
                    "measured_content_shift": String(describing: measured),
                    "loss_points": String(describing: loss),
                    "viewport": homeAuditFrame(viewport)])
            }
            ledger.observedFrames.append(afterFrames)
        }
        let finalViewport = try homeAuditViewport(app)
        let finalFrames = try homeAuditRecoveryFrames(leaves, in: app)
        let reachable = try homeAuditReachableRange(finalFrames, target: anchor.key, ledger: ledger)
        let pose = try homeAuditRecoveryPose(finalFrames, outstanding: outstandingKeys,
            pending: ledger.pending, viewport: finalViewport, reachable: reachable,
            auditedFrames: ledger.auditedFrames)
        try requireHomeAudit(pose.shift == 0
            && homeAuditBoundaryCrossings(finalFrames, viewport: finalViewport).isEmpty,
            "Bounded scrolling did not reach the selected measured gap-aligned Home pose")
        for target in outstanding where pose.visibleOutstanding.contains(target.key) {
            let element = try resolveHomeAuditLeaf(target, in: app)
            try requireHomeAudit(finalViewport.contains(element.frame) && element.isHittable,
                "Bounded recovery target is not fully visible and hittable: \(target.key)")
        }
        return pose.visibleOutstanding.sorted()
    }

    private func attachHomeAuditJSON(_ name: String, _ value: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not retain Home audit evidence: \(error)")
        }
    }

    @MainActor
    private func attachHomeAuditScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchQAApplication(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--lumina-ui-qa", "-appLanguage", "en"] + additionalArguments
        app.launchEnvironment["LUMINA_QA_ID"] = UUID().uuidString
        app.launch()
        // Fail closed: a normal production build must never run destructive fixture tests.
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    func testSaveRelaunchAndDeleteOnlyIsolatedFixtureRecords() throws {
        let app = launchQAApplication()
        app.tabBars.buttons["Nutrition"].tap()
        let meal = app.textFields["What did you eat?"]
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        meal.typeText("QA fixture meal")
        XCTAssertEqual(meal.value as? String, "QA fixture meal")
        try dismissRecordKeyboard(in: app)
        for _ in 0..<3 {
            if app.buttons["Save Meal"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Save Meal"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Meals logged today: 1"].exists)
        app.buttons["lumina.settings"].tap()
        let request = app.buttons["lumina.delete.request"]
        if !request.isHittable { app.swipeUp() }
        request.tap()
        XCTAssertTrue(app.staticTexts["Delete all local Lumina records and photos?"].waitForExistence(timeout: 5))
        // SwiftUI exposes a native wrapper and its actionable child with the same ID.
        let actions = app.buttons.matching(identifier: "lumina.delete.confirm").allElementsBoundByIndex
            .filter { $0.descendants(matching: .button).count == 0 }
        XCTAssertEqual(actions.count, 1)
        try XCTUnwrap(actions.first).tap()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Meals logged today: 0"].exists)
    }

    @MainActor
    func testPrivacyInformationAtLargestTextAndBackNavigation() throws {
        let app = launchQAApplication(additionalArguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ])
        app.buttons["lumina.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let privacyLink = app.buttons["lumina.privacy"]
        XCTAssertTrue(privacyLink.isHittable, "Privacy must be immediately reachable at the largest text size")
        XCTAssertEqual(privacyLink.label, "Privacy and your data")
        XCTAssertGreaterThanOrEqual(privacyLink.frame.height, 44)
        for _ in 0..<6 {
            if privacyLink.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(privacyLink.isHittable)
        privacyLink.tap()
        let privacyNavigation = app.navigationBars["Privacy and your data"]
        XCTAssertTrue(privacyNavigation.waitForExistence(timeout: 5))
        let heading = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Your journal")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.isHittable)
        XCTAssertGreaterThan(heading.frame.height, 0)
        XCTAssertGreaterThanOrEqual(heading.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(heading.frame.maxX, app.frame.maxX)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Privacy information at largest text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // The page has no custom toolbar actions; its first navigation button is Back.
        let back = privacyNavigation.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // A separate QA preference store exercises Arabic at the same real
        // app text-size override without changing another test's saved choice.
        app.terminate()
        let arabicApp = XCUIApplication()
        arabicApp.launchArguments = ["--lumina-ui-qa", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        arabicApp.launchEnvironment["LUMINA_QA_ID"] = UUID().uuidString
        arabicApp.launch()
        XCTAssertTrue(arabicApp.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try tapRecordControl(arabicApp.buttons["lumina.settings"], in: arabicApp)
        XCTAssertTrue(arabicApp.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        let arabicPrivacy = arabicApp.buttons["lumina.privacy"]
        XCTAssertTrue(arabicPrivacy.isHittable, "The same privacy route must be immediately reachable in Arabic at largest text")
        XCTAssertEqual(arabicPrivacy.label, "الخصوصية وبياناتك")
        XCTAssertGreaterThanOrEqual(arabicPrivacy.frame.height, 44)
        arabicPrivacy.tap()
        let arabicNavigation = arabicApp.navigationBars["الخصوصية وبياناتك"]
        XCTAssertTrue(arabicNavigation.waitForExistence(timeout: 5))
        let arabicHeading = arabicApp.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "يومياتك")).firstMatch
        XCTAssertTrue(arabicHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(arabicHeading.isHittable)
        XCTAssertGreaterThanOrEqual(arabicHeading.frame.minX, arabicApp.frame.minX)
        XCTAssertLessThanOrEqual(arabicHeading.frame.maxX, arabicApp.frame.maxX)
        let arabicBack = arabicNavigation.buttons.firstMatch
        XCTAssertTrue(arabicBack.isHittable)
        attachRecordScreenshot(arabicApp, "Arabic privacy information at largest text")
        arabicBack.tap()
        XCTAssertTrue(arabicApp.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        arabicApp.terminate()
    }

    @MainActor
    func testSuggestedHabitPersistsWithoutAutomaticCompletion() throws {
        let app = launchQAApplication()
        openHabits(in: app)
        let ideas = app.buttons["Browse habit ideas"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 5))
        ideas.tap()
        XCTAssertTrue(app.navigationBars["Habit ideas"].waitForExistence(timeout: 5))
        // This isolated empty fixture receives the fixed offline list in source order.
        let habitName = "Morning sunlight exposure"
        XCTAssertTrue(app.staticTexts[habitName].waitForExistence(timeout: 5))
        let addHabit = app.buttons.matching(identifier: "Add This Habit").firstMatch
        for _ in 0..<3 {
            if addHabit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(addHabit.isHittable)
        addHabit.tap()
        app.navigationBars["Habit ideas"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts[habitName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last recorded streak: 0 days"].exists)

        // Keep the same launch environment/UUID: this relaunch must reopen only this fixture.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        openHabits(in: app)
        XCTAssertTrue(app.staticTexts[habitName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Last recorded streak: 0 days"].exists)
        let completion = app.buttons["Mark \(habitName) complete for today"]
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertEqual(completion.value as? String, "Not completed today")
    }

    @MainActor
    func testFinalHomeLinkRemainsReachableAboveTabBar() throws {
        let app = launchQAApplication()
        let home = app.navigationBars["Lumina"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let finalLink = app.buttons["Training suggestions"]
        XCTAssertTrue(finalLink.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if finalLink.isHittable,
               finalLink.frame.minY >= home.frame.maxY,
               finalLink.frame.maxY <= tabBar.frame.minY { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(finalLink.isHittable)
        XCTAssertGreaterThanOrEqual(finalLink.frame.minY, home.frame.maxY)
        XCTAssertLessThanOrEqual(finalLink.frame.maxY, tabBar.frame.minY)
        let visibleLink = XCTAttachment(screenshot: app.screenshot())
        visibleLink.name = "Final Home link visible above tab bar"
        visibleLink.lifetime = .keepAlways
        add(visibleLink)
        finalLink.tap()
        XCTAssertTrue(app.navigationBars["Adaptive Plan"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHomeShortcutsReuseTabsAndRetainUnsavedRecords() throws {
        let app = launchQAApplication()
        app.tabBars.buttons["Workouts"].tap()
        let workout = app.textFields["lumina.workout.new-name"]
        try tapRecordControl(workout, in: app)
        workout.typeText("Shared workout draft")
        try dismissRecordKeyboard(in: app)
        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Log workout", in: app)
        XCTAssertTrue(app.tabBars.buttons["Workouts"].isSelected,
                      "The Home shortcut must select the existing tab rather than push a second form")
        XCTAssertEqual(workout.value as? String, "Shared workout draft")

        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Log meal", in: app)
        XCTAssertTrue(app.tabBars.buttons["Nutrition"].isSelected)
        let meal = app.textFields["lumina.meal.new-name"]
        try tapRecordControl(meal, in: app)
        meal.typeText("Shared meal draft")
        try dismissRecordKeyboard(in: app)
        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Log meal", in: app)
        XCTAssertTrue(app.tabBars.buttons["Nutrition"].isSelected)
        XCTAssertEqual(meal.value as? String, "Shared meal draft")

        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Offline coach", in: app)
        XCTAssertTrue(app.tabBars.buttons["Coach"].isSelected)
        XCTAssertTrue(app.textFields["lumina.coach.message"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Progress photos", in: app)
        XCTAssertTrue(app.tabBars.buttons["Progress"].isSelected)
        XCTAssertTrue(app.staticTexts["lumina.progress.empty"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Home"].tap()
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("العربية", in: app)
        app.navigationBars["الإعدادات"].buttons["Lumina"].tap()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 5))
        try tapRecordControl(app.buttons["تسجيل تمرين"], in: app, scrollDown: true)
        XCTAssertTrue(app.tabBars.buttons["التمارين"].isSelected)
        XCTAssertEqual(workout.value as? String, "Shared workout draft")
        app.tabBars.buttons["الرئيسية"].tap()
        try openRecordHomeLink("تسجيل وجبة", in: app)
        XCTAssertTrue(app.tabBars.buttons["التغذية"].isSelected)
        XCTAssertEqual(meal.value as? String, "Shared meal draft")
        attachRecordScreenshot(app, "Arabic Home shortcut retains the existing meal draft")
    }

    @MainActor
    private func openHabits(in app: XCUIApplication) {
        let habits = app.buttons["Habits"]
        XCTAssertTrue(habits.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if habits.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(habits.isHittable)
        habits.tap()
    }


    @MainActor
    func testFullJournalEditCancelAndRelaunch() throws {
        let app = launchQAApplication()
        try openRecordHomeLink("Journal", in: app)
        try tapRecordControl(app.buttons["lumina.journal.add"], in: app)
        let field = app.textViews["lumina.journal.new-content"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = "Fixture line one\nFixture line two\nFixture line three\nFixture line four\nExact final line"
        field.tap();field.typeText(original)
        try tapRecordControl(try recordLeafButton("lumina.journal.new-save", in: app), in: app)
        let row = app.staticTexts[original]
        try tapRecordControl(row, in: app)
        let full = app.textViews["lumina.journal.full-content"]
        XCTAssertEqual(full.value as? String, original)
        full.tap();full.typeText(" CANCELED")
        app.navigationBars["Journal entry"].buttons["Cancel"].tap()
        try tapRecordControl(app.staticTexts[original], in: app)
        XCTAssertEqual(full.value as? String, original)
        full.tap();full.typeText(" SAVED-EDIT")
        let edited = try XCTUnwrap(full.value as? String)
        XCTAssertTrue(edited.contains("SAVED-EDIT"))
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Journal", in: app)
        try tapRecordControl(app.staticTexts[edited], in: app)
        XCTAssertEqual(app.textViews["lumina.journal.full-content"].value as? String, edited)
        attachRecordScreenshot(app, "Full saved journal after relaunch")
        let savedMood = app.buttons["lumina.journal.record-mood"]
        for _ in 0..<8 {
            if savedMood.exists && savedMood.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(savedMood.exists && savedMood.isHittable)
        XCTAssertEqual(savedMood.value as? String, "Not recorded",
                       "Writing a journal entry without choosing a mood must never record Good automatically")
        XCTAssertGreaterThanOrEqual(savedMood.frame.height, 44)
        savedMood.tap()
        try tapRecordControl(app.buttons["Good"], in: app)
        XCTAssertEqual(savedMood.value as? String, "Good")
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Journal", in: app)
        try tapRecordControl(app.staticTexts[edited], in: app)
        for _ in 0..<8 {
            if savedMood.exists && savedMood.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(savedMood.exists && savedMood.isHittable)
        XCTAssertEqual(savedMood.value as? String, "Good",
                       "An explicitly chosen mood must survive the real save and relaunch")
    }

    @MainActor
    func testGoalValuesEditRelaunchAndConfirmedDeletion() throws {
        let app = launchQAApplication()
        try openRecordHomeLink("Goals", in: app)
        try tapRecordControl(app.buttons["lumina.goal.add"], in: app)
        // Missing name must show an error without leaving the draft.
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        XCTAssertTrue(app.alerts.staticTexts["Enter a goal name."].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        let name = app.textFields["lumina.goal.name"]
        name.tap();name.typeText("Fixture goal")
        let current = app.textFields["lumina.goal.current"]
        try replaceShortNumericRecordField(current, with: "2", in: app)
        let target = app.textFields["lumina.goal.target"]
        try replaceShortNumericRecordField(target, with: "5", in: app)
        XCTAssertEqual(Double(current.value as? String ?? ""), 2)
        XCTAssertEqual(Double(target.value as? String ?? ""), 5)
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        try tapRecordControl(app.buttons["Edit goal Fixture goal"], in: app)
        XCTAssertEqual(Double(app.textFields["lumina.goal.current"].value as? String ?? ""), 2)
        XCTAssertEqual(Double(app.textFields["lumina.goal.target"].value as? String ?? ""), 5)
        name.tap();name.typeText("-edited")
        let editedName = try XCTUnwrap(name.value as? String)
        XCTAssertTrue(editedName.contains("-edited"))
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Goals", in: app)
        try tapRecordControl(app.buttons["Edit goal \(editedName)"], in: app)
        XCTAssertEqual(Double(app.textFields["lumina.goal.current"].value as? String ?? ""), 2)
        XCTAssertEqual(Double(app.textFields["lumina.goal.target"].value as? String ?? ""), 5)
        try tapRecordControl(app.buttons["Delete this record"], in: app)
        try tapRecordControl(try recordLeafButton("Delete record", in: app), in: app)
        XCTAssertTrue(app.staticTexts["No goals yet. Add a goal to record what you want to work toward."].waitForExistence(timeout: 5))

        // The saved fraction must remain visible, not be rounded to a zero
        // target by the card while the editor still stores a different value.
        try tapRecordControl(app.buttons["lumina.goal.add"], in: app)
        let fractionalName = app.textFields["lumina.goal.name"]
        try tapRecordControl(fractionalName, in: app)
        fractionalName.typeText("Fractional fixture goal")
        try replaceShortNumericRecordField(app.textFields["lumina.goal.current"], with: "0.125", in: app)
        try replaceShortNumericRecordField(app.textFields["lumina.goal.target"], with: "0.25", in: app)
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        let values = app.staticTexts["lumina.goal.values"]
        XCTAssertTrue(values.waitForExistence(timeout: 5))
        XCTAssertEqual(values.label, "0.125 completion / 0.25 completion")
        XCTAssertTrue(values.isHittable)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Goals", in: app)
        XCTAssertEqual(values.label, "0.125 completion / 0.25 completion")
        try tapRecordControl(app.buttons["Edit goal Fractional fixture goal"], in: app)
        XCTAssertEqual(app.textFields["lumina.goal.current"].value as? String, "0.125")
        XCTAssertEqual(app.textFields["lumina.goal.target"].value as? String, "0.25")
    }

    @MainActor
    func testAllSavedMealsRemainEditableBeyondTheRecentPreview() throws {
        let app = launchQAApplication()
        app.tabBars.buttons["Nutrition"].tap()
        for index in 0..<4 {
            let input = app.textFields["What did you eat?"]
            try tapRecordControl(input, in: app, scrollDown: true)
            input.typeText("Fixture meal \(index)")
            try dismissRecordKeyboard(in: app)
            try tapRecordControl(app.buttons["Save Meal"], in: app)
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons["OK"].tap()
        }
        try tapRecordControl(app.buttons["lumina.meal.history"], in: app, scrollDown: true)
        for index in 0..<4 { XCTAssertTrue(app.staticTexts["Fixture meal \(index)"].exists) }
        try tapRecordControl(app.staticTexts["Fixture meal 0"], in: app)
        let notes = app.textViews["lumina.meal.record-notes"]
        notes.tap();notes.typeText("Saved meal detail beyond preview")
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["Meals logged today: 4"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Nutrition"].tap()
        try tapRecordControl(app.buttons["lumina.meal.history"], in: app)
        try tapRecordControl(app.staticTexts["Fixture meal 0"], in: app)
        XCTAssertEqual(app.textViews["lumina.meal.record-notes"].value as? String, "Saved meal detail beyond preview")
        attachRecordScreenshot(app, "Saved meal details after relaunch")
        try tapRecordControl(app.buttons["Delete this record"], in: app)
        try tapRecordControl(try recordLeafButton("Delete record", in: app), in: app)
        XCTAssertFalse(app.staticTexts["Fixture meal 0"].exists)
        for index in 1..<4 { XCTAssertTrue(app.staticTexts["Fixture meal \(index)"].exists) }
    }

    @MainActor
    func testOptionalMealNutritionDistinguishesMissingValuesFromExplicitZero() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--lumina-ui-qa", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LUMINA_QA_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Nutrition"].tap()
        try auditMealHeaderContrast(app, arabic: false, state: "English collapsed meal header")
        try auditMealFieldContrast(app, expected: [mealFieldExpectations(arabic: false)[0]],
                                   state: "English empty meal name")
        let name = app.textFields["lumina.meal.new-name"]
        try tapRecordControl(name, in: app)
        name.typeText("Unrecorded nutrition fixture")
        assertMealLabelWhileEditing(app, suffix: "name", label: "What did you eat?")
        try dismissRecordKeyboard(in: app)
        try auditMealFieldContrast(app,
            expected: [mealFieldExpectations(arabic: false, name: "Unrecorded nutrition fixture")[0]],
            state: "English populated meal name keeps its label")
        // Do not open or touch the optional nutrition controls before Save.
        try tapRecordControl(app.buttons["lumina.meal.new-save"], in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Nutrition"].tap()
        try tapRecordControl(app.buttons["lumina.meal.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Unrecorded nutrition fixture"], in: app)
        for identifier in ["lumina.meal.record-calories", "lumina.meal.record-protein"] {
            let field = app.textFields[identifier]
            try tapRecordControl(field, in: app)
            let value = try XCTUnwrap(field.value as? String)
            XCTAssertTrue(value.isEmpty || value == field.placeholderValue,
                          "An untouched nutrition value must remain absent after relaunch, never become zero")
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("العربية", in: app)
        app.tabBars.buttons["التغذية"].tap()
        try auditMealHeaderContrast(app, arabic: true, state: "Arabic collapsed meal header")
        try tapRecordControl(name, in: app)
        name.typeText("Explicit nutrition fixture")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(try recordLeafButton("lumina.meal.nutrition", in: app), in: app)
        try auditMealFieldContrast(app,
            expected: mealFieldExpectations(arabic: true, name: "Explicit nutrition fixture"),
            state: "Arabic empty nutrition prompts on English-region device")
        let standardMealLabelHeight = app.staticTexts["lumina.meal.new-name-label"].frame.height
        XCTAssertGreaterThan(standardMealLabelHeight, 0)
        let calories = app.textFields["lumina.meal.new-calories"]
        try tapRecordControl(calories, in: app)
        calories.typeText("0")
        XCTAssertEqual(calories.value as? String, "0")
        assertMealLabelWhileEditing(app, suffix: "calories", label: "السعرات الحرارية")
        try dismissRecordKeyboard(in: app)
        let protein = app.textFields["lumina.meal.new-protein"]
        try tapRecordControl(protein, in: app)
        protein.typeText("١٢٫٥")
        XCTAssertEqual(protein.value as? String, "١٢٫٥")
        assertMealLabelWhileEditing(app, suffix: "protein", label: "البروتين بالغرام")
        try dismissRecordKeyboard(in: app)
        try auditMealFieldContrast(app,
            expected: mealFieldExpectations(arabic: true, name: "Explicit nutrition fixture",
                                            calories: "0", protein: "١٢٫٥"),
            state: "Arabic populated meal fields retain labels and exact draft values")
        try tapRecordControl(app.buttons["lumina.meal.new-save"], in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["حسناً"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["يومياتك"].waitForExistence(timeout: 5))
        app.tabBars.buttons["التغذية"].tap()
        try tapRecordControl(app.buttons["lumina.meal.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Explicit nutrition fixture"], in: app)
        let savedCalories = app.textFields["lumina.meal.record-calories"]
        try tapRecordControl(savedCalories, in: app)
        XCTAssertEqual(savedCalories.value as? String, "0٫0",
                       "An explicit zero is a recorded value, distinct from an untouched field")
        let savedProtein = app.textFields["lumina.meal.record-protein"]
        try tapRecordControl(savedProtein, in: app)
        XCTAssertEqual(savedProtein.value as? String, "12٫5")
        attachRecordScreenshot(app, "Explicit Arabic nutrition values preserved after relaunch")

        // Cover the actual expanded form at the largest accessibility size;
        // this reuses the isolated store and the user's real persisted Arabic choice.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["يومياتك"].waitForExistence(timeout: 5))
        app.tabBars.buttons["التغذية"].tap()
        try auditMealHeaderContrast(app, arabic: true,
                                    state: "Arabic collapsed meal header at largest accessibility size")
        try tapRecordControl(try recordLeafButton("lumina.meal.nutrition", in: app), in: app)
        try auditMealFieldContrast(app, expected: mealFieldExpectations(arabic: true),
                                   state: "Arabic empty meal form at largest accessibility size")
        XCTAssertGreaterThan(app.staticTexts["lumina.meal.new-name-label"].frame.height,
                             standardMealLabelHeight,
                             "The persistent meal label must grow with Dynamic Type")
        try tapRecordControl(name, in: app, scrollDown: true)
        name.typeText("تفاح")
        assertMealLabelWhileEditing(app, suffix: "name", label: "ماذا أكلت؟")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(calories, in: app)
        calories.typeText("0")
        assertMealLabelWhileEditing(app, suffix: "calories", label: "السعرات الحرارية")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(protein, in: app)
        protein.typeText("١٢٫٥")
        assertMealLabelWhileEditing(app, suffix: "protein", label: "البروتين بالغرام")
        try dismissRecordKeyboard(in: app)
        try auditMealFieldContrast(app,
            expected: mealFieldExpectations(arabic: true, name: "تفاح", calories: "0", protein: "١٢٫٥"),
            state: "Arabic populated meal form at largest accessibility size")
    }

    private struct MealFieldExpectation {
        let suffix: String
        let label: String
        let prompt: String
        let value: String?
        var fieldID: String { "lumina.meal.new-\(suffix)" }
        var labelID: String { fieldID + "-label" }
    }

    private func mealFieldExpectations(arabic: Bool, name: String? = nil,
                                      calories: String? = nil, protein: String? = nil) -> [MealFieldExpectation] {
        let empty = arabic ? "غير مسجل" : "Not recorded"
        return [
            MealFieldExpectation(suffix: "name", label: arabic ? "ماذا أكلت؟" : "What did you eat?",
                                 prompt: arabic ? "اسم الوجبة" : "Meal name", value: name),
            MealFieldExpectation(suffix: "calories", label: arabic ? "السعرات الحرارية" : "Calories",
                                 prompt: empty, value: calories),
            MealFieldExpectation(suffix: "protein", label: arabic ? "البروتين بالغرام" : "Protein in grams",
                                 prompt: empty, value: protein),
        ]
    }

    // Credit the actual title and history action in their natural upper pose,
    // before editing or expanding nutrition. Later field/summary audits may
    // legitimately scroll this header offscreen; those cannot cover it here.
    @MainActor
    private func auditMealHeaderContrast(_ app: XCUIApplication, arabic: Bool, state: String) throws {
        let titleText = arabic ? "تسجيل وجبة" : "Log Meal"
        let historyText = arabic ? "عرض جميع الوجبات المحفوظة" : "View all saved meals"
        let collapsedValue = arabic ? "مطوي" : "Collapsed"
        let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first)
        let titles = scroll.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Log Meal", "تسجيل وجبة"))
        XCTAssertTrue(titles.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(titles.count, 1, "The actual localized meal title must be unique")
        let title = try XCTUnwrap(titles.allElementsBoundByIndex.first)
        let history = try recordLeafButton("lumina.meal.history", in: app)
        let nutrition = try recordLeafButton("lumina.meal.nutrition", in: app)
        let expectedName = mealFieldExpectations(arabic: arabic)[0]
        let name = app.textFields[expectedName.fieldID]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let originalDraft = try XCTUnwrap(name.value as? String)
        XCTAssertTrue(originalDraft.isEmpty || originalDraft == expectedName.prompt,
                      "The initial upper audit must preserve the real untouched meal draft")

        @MainActor
        func recordEvidence(_ phase: String, viewport: CGRect) {
            attachRecordScreenshot(app, state + " — " + phase + " header contrast audit")
            let evidence = XCTAttachment(string: "Required header targets: title and lumina.meal.history\n"
                + "State: \(state)\nViewport: \(viewport)\n"
                + "Title: \(title.label), frame: \(title.frame)\n"
                + "History: \(history.label), frame: \(history.frame)\n"
                + "Nutrition state: \(String(describing: nutrition.value))\n"
                + "Draft before audit: \(originalDraft)\n" + app.debugDescription)
            evidence.name = state + " — " + phase + " measured header coverage"
            evidence.lifetime = .keepAlways
            add(evidence)
        }

        @MainActor
        func requireHeaderPose(_ viewport: CGRect) {
            XCTAssertFalse(app.keyboards.firstMatch.exists,
                           "The real keyboard must be absent from the header audit")
            XCTAssertEqual(title.label, titleText)
            XCTAssertEqual(history.label, historyText)
            for element in [title, history] {
                let frame = element.frame
                XCTAssertTrue(element.exists && element.isHittable
                    && !frame.isEmpty && !frame.isNull && !frame.isInfinite
                    && viewport.contains(frame),
                    "The complete actual title and history action must be readable inside the measured safe viewport; offscreen or clipped content earns no header coverage")
            }
            XCTAssertEqual(nutrition.value as? String, collapsedValue,
                           "Audit the genuine collapsed composer without toggling or resetting its state")
            for field in mealFieldExpectations(arabic: arabic).dropFirst() {
                XCTAssertFalse(app.textFields[field.fieldID].exists,
                               "The upper audit must not expand optional nutrition")
                XCTAssertFalse(app.staticTexts[field.labelID].exists)
            }
            XCTAssertEqual(name.label, expectedName.label)
            XCTAssertEqual(name.placeholderValue, expectedName.prompt)
            XCTAssertEqual(name.value as? String, originalDraft,
                           "A contrast audit must not replace or reset the real meal draft")
        }

        // R17's real one-page collapsed form exposes this native track too.
        // Require measured bounds rather than crediting content under a status
        // or tab bar; never move, hide, shrink or filter an element for this audit.
        let before = try mealAuditViewport(app, requireScrollTrack: true)
        recordEvidence("before", viewport: before)
        requireHeaderPose(before)
        try app.performAccessibilityAudit(for: .contrast)
        let after = try mealAuditViewport(app, requireScrollTrack: true)
        recordEvidence("after", viewport: after)
        requireHeaderPose(after)
    }

    @MainActor
    private func mealAuditViewport(_ app: XCUIApplication,
                                   requireScrollTrack: Bool = false) throws -> CGRect {
        let scrolls = app.scrollViews.allElementsBoundByIndex
        XCTAssertEqual(scrolls.count, 1, "Meal audit requires the real form's single scroll view")
        let scroll = try XCTUnwrap(scrolls.first)
        let frame = app.frame.intersection(scroll.frame)
        var top = frame.minY
        var bottom = frame.maxY
        for bar in app.statusBars.allElementsBoundByIndex + app.navigationBars.allElementsBoundByIndex {
            if !bar.frame.isEmpty && bar.frame.intersects(frame) {
                top = max(top, bar.frame.maxY)
            }
        }
        for bar in app.tabBars.allElementsBoundByIndex {
            if !bar.frame.isEmpty && bar.frame.intersects(frame) {
                bottom = min(bottom, bar.frame.minY)
            }
        }
        // This journey deliberately uses an English-region device. Its native
        // indicator track exposes the actual scrollable safe region even when
        // the status bar is not returned in the app's accessibility subtree.
        let tracks = scroll.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@",
            "Vertical scroll bar")).allElementsBoundByIndex.map(\.frame).filter {
                !$0.isEmpty && $0.height > $0.width && $0.intersects(frame)
            }
        if requireScrollTrack {
            XCTAssertFalse(tracks.isEmpty, "A covered-heading reveal needs measured native scroll-track bounds")
        }
        if let track = tracks.first {
            XCTAssertTrue(tracks.allSatisfy {
                abs($0.minY - track.minY) <= 1 && abs($0.maxY - track.maxY) <= 1
            }, "Native scroll indicators must agree on the usable vertical viewport")
            top = max(top, track.minY)
            bottom = min(bottom, track.maxY)
        }
        let viewport = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
        XCTAssertTrue(!viewport.isNull && !viewport.isInfinite && viewport.width > 0 && viewport.height > 0,
                      "Meal audit needs an unobscured visible viewport")
        return viewport
    }

    @MainActor
    private func mealPairIsVisible(_ expected: MealFieldExpectation, in app: XCUIApplication,
                                   viewport: CGRect) -> Bool {
        let label = app.staticTexts[expected.labelID]
        let field = app.textFields[expected.fieldID]
        return label.exists && field.exists && label.isHittable && field.isHittable
            && !label.frame.isEmpty && !field.frame.isEmpty
            && viewport.contains(label.frame) && viewport.contains(field.frame)
    }

    @MainActor
    private func revealMealRecentSummaryForAudit(_ app: XCUIApplication,
                                                 preserving fields: [MealFieldExpectation],
                                                 state: String) throws -> [XCUIElement] {
        let scroll = try XCTUnwrap(app.scrollViews.allElementsBoundByIndex.first)
        let headings = scroll.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Recent Meals", "الوجبات الأخيرة")).allElementsBoundByIndex
        guard !headings.isEmpty else { return [] } // The initial journal has no recent meals.
        XCTAssertEqual(headings.count, 1, "The actual recent-meals heading must be unique")
        let heading = try XCTUnwrap(headings.first)
        let bars = app.tabBars.allElementsBoundByIndex.filter { !$0.frame.isEmpty }
        guard bars.contains(where: { $0.frame.intersects(heading.frame) }) else { return [] }

        // R15's native crop was the floating tab bar covering this heading.
        // Reveal the real summary, including its rows, so moving the heading
        // cannot merely replace it with a covered row. Keep every field pair
        // already eligible for this audit in the same measured visible region.
        let summary = scroll.staticTexts.allElementsBoundByIndex.filter {
            !$0.frame.isEmpty && $0.frame.minY >= heading.frame.minY
        }
        let targets = fields.flatMap { [app.staticTexts[$0.labelID], app.textFields[$0.fieldID]] } + summary
        let labels = summary.map(\.label)
        let initialViewport = try mealAuditViewport(app, requireScrollTrack: true)
        let interior = initialViewport.insetBy(dx: 0, dy: 2)
        let physicalWindow = app.frame
        let titles = scroll.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Log Meal", "تسجيل وجبة")).allElementsBoundByIndex
        XCTAssertEqual(titles.count, 1, "The real meal heading must remain present and unique")
        let title = try XCTUnwrap(titles.first)
        let originalTitle = title.label
        let originalTitleSize = title.frame.size
        func unionFrame() -> CGRect { targets.reduce(CGRect.null) { $0.union($1.frame) } }
        func overflow(_ frame: CGRect) -> CGFloat {
            max(0, interior.minY - frame.minY) + max(0, frame.maxY - interior.maxY)
        }
        func titleClearance() -> CGFloat {
            let frame = title.frame
            XCTAssertTrue(title.exists && !frame.isEmpty && !frame.isNull && !frame.isInfinite,
                          "Scrolling must retain the actual heading and its measured frame")
            // R17 left only 0.4pt of this heading inside the physical screen.
            // Audit a real readable heading or a scroll position where it is
            // fully offscreen, never its clipped pixels. No AX element is hidden.
            if interior.contains(frame) || frame.maxY <= physicalWindow.minY - 2 + 0.000001 { return 0 }
            XCTAssertLessThanOrEqual(frame.maxY, interior.minY,
                "A title clearance must concern the heading already above the audited safe viewport")
            return max(0, frame.maxY - physicalWindow.minY + 2)
        }
        func plannedContentDisplacement(_ frame: CGRect) throws -> CGFloat {
            let headingFrame = title.frame
            let unionLower = frame.maxY - interior.maxY
            let unionUpper = frame.minY - interior.minY
            XCTAssertTrue(unionLower.isFinite && unionUpper.isFinite
                && headingFrame.minY.isFinite && headingFrame.maxY.isFinite)
            XCTAssertLessThanOrEqual(unionLower, unionUpper,
                "The entire preserved region must have a feasible displacement")
            var intervals: [(lower: CGFloat, upper: CGFloat)] = []
            func include(_ lower: CGFloat, _ upper: CGFloat) {
                let start = max(unionLower, lower)
                let end = min(unionUpper, upper)
                if start <= end { intervals.append((start, end)) }
            }
            // Positive displacement moves content upward. Plan both edges
            // before the first drag: R18's 12pt follow-up moved content 30pt.
            // Preserve a readable title or clear it above the physical window,
            // while keeping every current field and summary inside the viewport.
            include(headingFrame.maxY - interior.maxY, headingFrame.minY - interior.minY)
            include(headingFrame.maxY - physicalWindow.minY + 2, unionUpper)
            let candidates = intervals.map { interval -> CGFloat in
                if interval.lower <= 0 && interval.upper >= 0 { return 0 }
                return interval.lower + (interval.upper - interval.lower) / 2
            }
            let selected = try XCTUnwrap(candidates.min { abs($0) < abs($1) },
                "Title clearance and complete field/summary coverage must fit together")
            XCTAssertTrue(selected.isFinite)
            return selected
        }
        let initialUnion = unionFrame()
        var evidence = ["State: \(state)", "Summary labels: \(labels)",
                        "Initial viewport: \(initialViewport)", "Initial union: \(initialUnion)",
                        "Physical window: \(physicalWindow)", "Initial heading: \(title.frame)"]
        defer {
            let attachment = XCTAttachment(string: evidence.joined(separator: "\n") + "\n" + app.debugDescription)
            attachment.name = state + " — measured recent-summary reveal"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        attachRecordScreenshot(app, state + " — recent summary covered by tab bar")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(targets.allSatisfy { $0.exists && !$0.frame.isEmpty })
        XCTAssertTrue(!initialUnion.isNull && !initialUnion.isInfinite && initialUnion.height > 0)
        XCTAssertLessThanOrEqual(initialUnion.height, interior.height,
            "The recent summary and all current field pairs must fit together; never drop audit coverage to make a pose fit")
        XCTAssertTrue(initialUnion.minX >= interior.minX && initialUnion.maxX <= interior.maxX)
        let step = interior.height * 0.25
        XCTAssertGreaterThan(step, 20)
        let budget = Int(ceil((overflow(initialUnion) + titleClearance()) / step)) + 2
        XCTAssertTrue((1...8).contains(budget), "A reveal must have a finite geometry-derived gesture budget")
        evidence.append("Gesture step: \(step); budget: \(budget)")
        for gesture in 0..<budget {
            let before = unionFrame()
            let beforeClearance = titleClearance()
            if interior.contains(before) && beforeClearance == 0 { break }
            if beforeClearance > 0 {
                XCTAssertGreaterThanOrEqual(before.minY - beforeClearance, interior.minY,
                    "Clearing a clipped heading cannot push any preserved field or summary out of this audit")
            }
            let beforeError = overflow(before) + beforeClearance
            let plannedDisplacement = try plannedContentDisplacement(before)
            XCTAssertGreaterThan(abs(plannedDisplacement), 0.000001,
                "A required reveal must plan real movement inside the feasible interval")
            let direction: CGFloat = plannedDisplacement > 0 ? -1 : 1
            let distance = min(step, abs(plannedDisplacement) + 10)
            let window = app.frame
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let startY = initialViewport.midY - direction * distance / 2
            let endY = initialViewport.midY + direction * distance / 2
            let controlFrames = (scroll.buttons.allElementsBoundByIndex
                + scroll.textFields.allElementsBoundByIndex + scroll.textViews.allElementsBoundByIndex).map(\.frame)
            let trackFrames = scroll.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@",
                "Vertical scroll bar")).allElementsBoundByIndex.map(\.frame)
            let obstacles = (controlFrames + trackFrames).filter { !$0.isEmpty }
            // Choose a real empty gutter from current frames, avoiding editable
            // fields, action buttons and the native indicator on either side.
            let x = try XCTUnwrap([initialViewport.maxX - 10, initialViewport.minX + 10].first { x in
                let route = CGRect(x: x - 1, y: min(startY, endY), width: 2, height: distance)
                return initialViewport.contains(route) && !obstacles.contains { $0.intersects(route) }
            }, "The measured scroll route must avoid every actual control and indicator")
            XCTAssertTrue(initialViewport.contains(CGPoint(x: x, y: startY))
                && initialViewport.contains(CGPoint(x: x, y: endY)))
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end,
                        withVelocity: .slow, thenHoldForDuration: 0.25)
            let after = unionFrame()
            let afterClearance = titleClearance()
            let afterError = overflow(after) + afterClearance
            evidence.append("Gesture \(gesture): direction=\(direction), plannedDisplacement=\(plannedDisplacement), travel=\(distance), routeX=\(x), startY=\(startY), endY=\(endY), obstacles=\(obstacles), before=\(before), after=\(after), heading=\(title.frame), headingClearance=\(afterClearance), remaining=\(afterError)")
            XCTAssertEqual(app.frame, window)
            let currentViewport = try mealAuditViewport(app, requireScrollTrack: true)
            // AX reports can differ by floating-point roundoff after a gesture.
            // One millionth of a point preserves the measured viewport invariant.
            let components: [(String, CGFloat, CGFloat)] = [
                ("x", currentViewport.minX, initialViewport.minX),
                ("y", currentViewport.minY, initialViewport.minY),
                ("width", currentViewport.width, initialViewport.width),
                ("height", currentViewport.height, initialViewport.height),
            ]
            for (name, current, initial) in components {
                XCTAssertTrue(current.isFinite && initial.isFinite,
                              "The measured viewport \(name) must remain finite")
                XCTAssertEqual(current, initial, accuracy: 0.000001,
                               "Scrolling must preserve the measured viewport \(name)")
            }
            XCTAssertEqual(summary.map(\.label), labels, "A reveal must not replace the actual summary content")
            XCTAssertEqual(title.label, originalTitle, "A pose must not replace the actual heading text")
            XCTAssertEqual(title.frame.width, originalTitleSize.width, accuracy: 1)
            XCTAssertEqual(title.frame.height, originalTitleSize.height, accuracy: 1)
            XCTAssertEqual(after.height, before.height, accuracy: 1, "Scrolling must not collapse or resize the form")
            XCTAssertGreaterThan((after.minY - before.minY) * direction, 0.5,
                                 "Every gesture must move the real content in the requested direction")
            XCTAssertLessThan(afterError, beforeError, "Every gesture must reduce the measured occlusion")
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        }
        let finalViewport = try mealAuditViewport(app, requireScrollTrack: true)
        XCTAssertTrue(interior.contains(unionFrame()), "The complete measured region must be exposed within the finite budget")
        XCTAssertEqual(titleClearance(), 0, "The real heading must be fully readable or fully outside the physical screen")
        XCTAssertTrue(targets.allSatisfy { $0.exists && $0.isHittable && finalViewport.contains($0.frame) },
                      "Every preserved label, field and summary row must be visible and hittable")
        XCTAssertTrue(fields.allSatisfy { mealPairIsVisible($0, in: app, viewport: finalViewport) },
                      "Revealing the summary cannot push an already visible field pair out of this audit")
        for element in summary {
            XCTAssertTrue(element.exists && element.isHittable && finalViewport.contains(element.frame),
                          "Every recent-summary label must be fully visible above the tab bar")
        }
        return summary
    }

    @MainActor
    private func auditMealFieldContrast(_ app: XCUIApplication,
                                       expected: [MealFieldExpectation], state: String) throws {
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Dismiss the real keyboard before a form contrast audit")
        XCTAssertEqual(Set(expected.map(\.fieldID)).count, expected.count)
        var covered: Set<String> = []
        for target in expected {
            if covered.contains(target.fieldID) { continue }
            _ = app.textFields[target.fieldID].waitForExistence(timeout: 5)
            var viewport = try mealAuditViewport(app)
            for _ in 0..<8 {
                if mealPairIsVisible(target, in: app, viewport: viewport) { break }
                let label = app.staticTexts[target.labelID]
                let field = app.textFields[target.fieldID]
                if (label.exists && label.frame.minY < viewport.minY)
                    || (field.exists && field.frame.minY < viewport.minY) {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
                viewport = try mealAuditViewport(app)
            }
            XCTAssertTrue(mealPairIsVisible(target, in: app, viewport: viewport),
                          "Both the persistent label and actual input must be fully visible after bounded scrolling")
            let visibleBeforeReveal = expected.filter { mealPairIsVisible($0, in: app, viewport: viewport) }
            let revealedSummary = try revealMealRecentSummaryForAudit(app, preserving: visibleBeforeReveal, state: state)
            viewport = try mealAuditViewport(app, requireScrollTrack: !revealedSummary.isEmpty)
            let visible = expected.filter { mealPairIsVisible($0, in: app, viewport: viewport) }
            XCTAssertTrue(visible.contains { $0.fieldID == target.fieldID })
            for item in visible {
                let field = app.textFields[item.fieldID]
                XCTAssertEqual(app.staticTexts[item.labelID].label, item.label)
                XCTAssertEqual(field.label, item.label, "The input name must match its persistent visible label")
                XCTAssertGreaterThanOrEqual(field.frame.width, 44)
                XCTAssertGreaterThanOrEqual(field.frame.height, 44)
                let value = try XCTUnwrap(field.value as? String)
                if let recorded = item.value {
                    XCTAssertEqual(value, recorded, "Auditing must preserve the exact entered draft")
                } else {
                    XCTAssertEqual(field.placeholderValue, item.prompt)
                    XCTAssertTrue(value.isEmpty || value == item.prompt,
                                  "An empty nutrition field must not silently become zero")
                }
            }
            attachRecordScreenshot(app, state + " — before contrast audit")
            let evidence = XCTAttachment(string: "Audited fields: \(visible.map(\.fieldID))\n"
                + "Viewport: \(viewport)\n" + app.debugDescription)
            evidence.name = state + " — visible meal fields"
            evidence.lifetime = .keepAlways
            add(evidence)
            // Run the real complete audit. No issue handler, exclusions or synthetic result.
            try app.performAccessibilityAudit(for: .contrast)
            let after = try mealAuditViewport(app, requireScrollTrack: !revealedSummary.isEmpty)
            for item in visible {
                XCTAssertTrue(mealPairIsVisible(item, in: app, viewport: after),
                              "A field cannot receive contrast credit after leaving the visible viewport")
            }
            for element in revealedSummary {
                XCTAssertTrue(element.exists && element.isHittable && after.contains(element.frame),
                              "A summary cannot receive contrast credit after leaving the visible viewport")
            }
            attachRecordScreenshot(app, state + " — after contrast audit")
            covered.formUnion(visible.map(\.fieldID))
        }
        XCTAssertEqual(covered, Set(expected.map(\.fieldID)), "Every requested field needs actual contrast coverage")
    }

    @MainActor
    private func assertMealLabelWhileEditing(_ app: XCUIApplication, suffix: String, label: String) {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let persistent = app.staticTexts["lumina.meal.new-\(suffix)-label"]
        XCTAssertEqual(persistent.label, label)
        XCTAssertTrue(persistent.isHittable, "The label must remain readable while the field is being edited")
        XCTAssertLessThanOrEqual(persistent.frame.maxY, app.keyboards.firstMatch.frame.minY,
                                 "The keyboard must not cover the persistent field label")
        attachRecordScreenshot(app, "Persistent \(suffix) label with keyboard")
    }

    @MainActor
    func testWorkoutExercisesSetsAndNotesRemainEditableAfterRelaunch() throws {
        let app = launchQAApplication()
        app.tabBars.buttons["Workouts"].tap()
        let name = app.textFields["lumina.workout.new-name"]
        try tapRecordControl(name, in: app);name.typeText("Fixture workout")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["Add exercise"], in: app)
        let exercise = app.textFields["Exercise name"]
        try tapRecordControl(exercise, in: app);exercise.typeText("Fixture squat")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["Add set"], in: app)
        let weight = app.textFields["Weight in kilograms for Fixture squat"]
        try tapRecordControl(weight, in: app);weight.typeText("25.5")
        try dismissRecordKeyboard(in: app)
        let notes = app.textFields["lumina.workout.new-notes"]
        try tapRecordControl(notes, in: app);notes.typeText("Full workout fixture notes")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5));app.alerts.buttons["OK"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["Workouts logged today: 1"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Workouts"].tap()
        try tapRecordControl(app.buttons["lumina.workout.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Fixture workout"], in: app)
        XCTAssertEqual(app.textViews["lumina.workout.record-notes"].value as? String, "Full workout fixture notes")
        try tapRecordControl(app.textFields["Exercise name"], in: app)
        XCTAssertEqual(app.textFields["Exercise name"].value as? String, "Fixture squat")
        XCTAssertEqual(Double(app.textFields["Weight in kilograms for Fixture squat"].value as? String ?? ""), 25.5)
        app.navigationBars["Saved workout"].buttons["Cancel"].tap()
        try tapRecordControl(app.collectionViews.staticTexts["Fixture workout"], in: app)
        let savedNotes = app.textViews["lumina.workout.record-notes"]
        savedNotes.tap();savedNotes.typeText(" EDITED")
        let edited = try XCTUnwrap(savedNotes.value as? String)
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Fixture workout"], in: app)
        XCTAssertEqual(app.textViews["lumina.workout.record-notes"].value as? String, edited)
        attachRecordScreenshot(app, "Saved workout details and sets")
    }

    @MainActor
    func testWorkoutEffortIsOptionalAndExplicitRatingSurvivesDraftLanguageAndRelaunch() throws {
        let app = launchQAApplication()
        app.tabBars.buttons["Workouts"].tap()
        let name = app.textFields["lumina.workout.new-name"]
        try tapRecordControl(name, in: app)
        name.typeText("Unrecorded effort fixture")
        try dismissRecordKeyboard(in: app)
        let notes = app.textFields["lumina.workout.new-notes"]
        try tapRecordControl(notes, in: app)
        notes.typeText("No effort rating was chosen")
        try dismissRecordKeyboard(in: app)
        // Do not touch any effort control. Inspect the persisted record, not a
        // label on the creation form: the old UI saved 7 and fails this check.
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts["Workout saved!"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Workouts logged today: 1"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Workouts"].tap()
        try tapRecordControl(app.buttons["lumina.workout.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Unrecorded effort fixture"], in: app)
        let unrecorded = app.textFields["lumina.workout.record-effort"]
        XCTAssertTrue(unrecorded.waitForExistence(timeout: 5))
        XCTAssertEqual(unrecorded.label, "Exertion 1–10 (optional)")
        XCTAssertTrue(unrecorded.isHittable, "The saved optional field must be reachable before reading its persisted value")
        let unrecordedValue = try XCTUnwrap(unrecorded.value as? String)
        XCTAssertTrue(unrecordedValue.isEmpty || unrecordedValue == unrecorded.placeholderValue,
                      "An untouched effort field must stay empty after saving and relaunching, never become 7 or 0")
        XCTAssertEqual(app.textViews["lumina.workout.record-notes"].value as? String,
                       "No effort rating was chosen")
        app.navigationBars["Saved workout"].buttons["Cancel"].tap()
        app.navigationBars["Saved workouts"].buttons["Done"].tap()

        // Validation failure must retain both an explicit rating and its notes.
        try tapRecordControl(notes, in: app)
        notes.typeText("Explicit effort draft notes")
        try dismissRecordKeyboard(in: app)
        let effort = try recordMenuButton("lumina.workout.new-effort", in: app)
        XCTAssertEqual(effort.label, "Effort (optional)")
        try tapRecordControl(effort, in: app, scrollDown: true)
        try tapRecordControl(app.buttons["6 of 10"], in: app)
        XCTAssertEqual(effort.value as? String, "6 of 10")
        let scale = app.staticTexts["lumina.workout.effort-scale"]
        XCTAssertTrue(scale.exists)
        let standardScaleHeight = scale.frame.height
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts.staticTexts["Enter a workout name."].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        let retainedError = app.staticTexts["lumina.workout.save-error"]
        XCTAssertTrue(retainedError.waitForExistence(timeout: 5))
        XCTAssertEqual(retainedError.label, "Enter a workout name.")
        XCTAssertEqual(effort.value as? String, "6 of 10")
        XCTAssertEqual(notes.value as? String, "Explicit effort draft notes")
        try tapRecordControl(name, in: app, scrollDown: true)
        name.typeText("Explicit effort fixture")
        try dismissRecordKeyboard(in: app)

        app.tabBars.buttons["Home"].tap()
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("العربية", in: app)
        app.tabBars.buttons["التمارين"].tap()
        XCTAssertEqual(name.value as? String, "Explicit effort fixture")
        XCTAssertEqual(notes.value as? String, "Explicit effort draft notes")
        XCTAssertTrue(retainedError.waitForExistence(timeout: 5))
        XCTAssertEqual(retainedError.label, "أدخل اسم التمرين.",
                       "The retained validation error must switch language without clearing or revalidating the draft")
        let arabicEffort = try recordMenuButton("lumina.workout.new-effort", in: app)
        XCTAssertEqual(arabicEffort.label, "الجهد (اختياري)")
        let arabicValue = try XCTUnwrap(arabicEffort.value as? String)
        let normalizedArabicValue = arabicValue.map { character in
            character.wholeNumberValue.map(String.init) ?? String(character)
        }.joined()
        XCTAssertEqual(normalizedArabicValue, "6 من 10",
                       "The selected effort must remain six while its accessible value switches to Arabic")
        attachRecordScreenshot(app, "Arabic optional effort and retained workout draft")
        app.tabBars.buttons["الرئيسية"].tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        try selectAppLanguage("English", in: app)
        app.tabBars.buttons["Workouts"].tap()
        XCTAssertEqual(name.value as? String, "Explicit effort fixture")
        XCTAssertTrue(retainedError.waitForExistence(timeout: 5))
        XCTAssertEqual(retainedError.label, "Enter a workout name.")
        XCTAssertEqual(effort.label, "Effort (optional)")
        XCTAssertEqual(effort.value as? String, "6 of 10")

        // Clearing a draft rating must be possible without discarding other fields.
        try tapRecordControl(effort, in: app)
        try tapRecordControl(app.buttons["Not recorded"], in: app)
        XCTAssertEqual(effort.value as? String, "Not recorded")
        XCTAssertEqual(notes.value as? String, "Explicit effort draft notes")
        try tapRecordControl(effort, in: app)
        try tapRecordControl(app.buttons["6 of 10"], in: app)
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts["Workout saved!"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(effort.value as? String, "Not recorded",
                       "A successful save must start the next draft without the previous rating")
        XCTAssertFalse(retainedError.exists, "A successful save must clear the previous validation error")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Workouts logged today: 2"].waitForExistence(timeout: 15),
                      "The failed validation attempt must not create a duplicate workout")
        app.tabBars.buttons["Workouts"].tap()
        try tapRecordControl(app.buttons["lumina.workout.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Explicit effort fixture"], in: app)
        let recorded = app.textFields["lumina.workout.record-effort"]
        XCTAssertTrue(recorded.waitForExistence(timeout: 5))
        XCTAssertEqual(recorded.label, "Exertion 1–10 (optional)")
        XCTAssertTrue(recorded.isHittable)
        XCTAssertEqual(recorded.value as? String, "6",
                       "An explicit effort rating must be retained in the persisted record")
        XCTAssertEqual(app.textViews["lumina.workout.record-notes"].value as? String,
                       "Explicit effort draft notes")
        attachRecordScreenshot(app, "Explicit effort preserved after relaunch")

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Workouts"].tap()
        let largeEffort = try recordMenuButton("lumina.workout.new-effort", in: app)
        try tapRecordControl(largeEffort, in: app)
        try tapRecordControl(app.buttons["6 of 10"], in: app)
        XCTAssertEqual(largeEffort.value as? String, "6 of 10",
                       "An explicit rating must be selectable at the largest accessibility text size")
        try tapRecordControl(largeEffort, in: app)
        try tapRecordControl(app.buttons["Not recorded"], in: app)
        XCTAssertTrue(largeEffort.exists && largeEffort.isHittable)
        XCTAssertGreaterThanOrEqual(largeEffort.frame.width, 44)
        XCTAssertGreaterThanOrEqual(largeEffort.frame.height, 44)
        XCTAssertEqual(largeEffort.value as? String, "Not recorded")
        XCTAssertTrue(scale.exists)
        XCTAssertGreaterThan(scale.frame.height, standardScaleHeight,
                             "The visible effort explanation must grow with accessibility text size")
        attachRecordScreenshot(app, "Optional effort at largest accessibility text size")
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts.staticTexts["Enter a workout name."].waitForExistence(timeout: 5),
                      "The real Save action must remain reachable after the expanded effort section")
        app.alerts.buttons["OK"].tap()
    }

    @MainActor
    func testManualHabitDuplicateErrorAndManagementPreserveRecords() throws {
        let app = launchQAApplication()
        openHabits(in: app)
        for attempt in 0..<2 {
            try tapRecordControl(app.buttons["lumina.habit.add"], in: app)
            XCTAssertTrue(app.navigationBars["New habit"].waitForExistence(timeout: 5))
            let input = app.textFields["lumina.habit.new-name"]
            input.tap();input.typeText(attempt == 0 ? "Manual fixture habit" : "MANUAL FIXTURE HABIT")
            try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
            if attempt == 1 {
                XCTAssertTrue(app.alerts.staticTexts["This habit is already in your list."].waitForExistence(timeout: 5))
                app.alerts.buttons["OK"].tap()
                XCTAssertEqual(input.value as? String, "MANUAL FIXTURE HABIT")
                app.navigationBars["New habit"].buttons["Cancel"].tap()
            }
        }
        try tapRecordControl(app.buttons["lumina.habit.history"], in: app, scrollDown: true)
        XCTAssertTrue(app.navigationBars["Manage habits"].waitForExistence(timeout: 5))
        // The same habit remains visible behind a half-height management sheet.
        // Count the saved management rows, not both presentation surfaces.
        let managedNames = app.staticTexts.matching(identifier: "lumina.habit.history-name")
            .matching(NSPredicate(format: "label == %@", "Manual fixture habit"))
        XCTAssertTrue(managedNames.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(managedNames.count, 1)
        try tapRecordControl(managedNames.element(boundBy: 0), in: app)
        XCTAssertTrue(app.staticTexts["Total recorded completions: 0"].exists)
        let name=app.textFields["lumina.habit.record-name"]
        name.tap();name.typeText("-edited")
        let edited=try XCTUnwrap(name.value as? String)
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        openHabits(in: app)
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Mark \(edited) complete for today"].value as? String, "Not completed today")
    }

    @MainActor
    func testSavedCheckInNoteEditRelaunchAndDeletion() throws {
        let app=launchQAApplication()
        try openRecordHomeLink("Daily check-in", in: app)
        let note=app.textViews["lumina.checkin.new-note"]
        try tapRecordControl(note, in: app);note.typeText("Complete check-in fixture note")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["lumina.checkin.new-save"], in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5));app.alerts.buttons["OK"].tap()
        try tapRecordControl(app.buttons["lumina.checkin.history"], in: app, scrollDown: true)
        try tapRecordControl(app.staticTexts["Complete check-in fixture note"], in: app)
        let full=app.textViews["lumina.checkin.record-note"]
        XCTAssertEqual(full.value as? String, "Complete check-in fixture note")
        full.tap();full.typeText(" EDITED")
        let edited=try XCTUnwrap(full.value as? String)
        try tapRecordControl(try recordLeafButton("lumina.record.save", in: app), in: app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Daily check-in", in: app)
        try tapRecordControl(app.buttons["lumina.checkin.history"], in: app)
        try tapRecordControl(app.staticTexts[edited], in: app)
        XCTAssertEqual(app.textViews["lumina.checkin.record-note"].value as? String, edited)
        try tapRecordControl(app.buttons["Delete this record"], in: app)
        try tapRecordControl(try recordLeafButton("Delete record", in: app), in: app)
        XCTAssertTrue(app.staticTexts["No saved check-ins."].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openRecordHomeLink(_ name: String, in app: XCUIApplication) throws {
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        try tapRecordControl(app.buttons[name], in: app)
    }

    @MainActor
    private func recordLeafButton(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(app.buttons.matching(identifier: identifier).firstMatch.waitForExistence(timeout: 5))
        let leaves=app.buttons.matching(identifier: identifier).allElementsBoundByIndex
            .filter { $0.descendants(matching: .button).count == 0 }
        XCTAssertEqual(leaves.count,1,"The requested record action must resolve uniquely")
        return try XCTUnwrap(leaves.first)
    }

    @MainActor
    private func recordMenuButton(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        // A native Menu can expose its Picker actions as button descendants.
        // Resolve the unique identified menu itself, then use the same real
        // visibility, scrolling, and tap checks as every other record control.
        let menus = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(menus.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(menus.count, 1, "The requested record menu must resolve uniquely")
        return try XCTUnwrap(menus.allElementsBoundByIndex.first)
    }

    @MainActor
    private func dismissRecordKeyboard(in app: XCUIApplication) throws {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let done = try recordLeafButton("lumina.keyboard.done", in: app)
        XCTAssertTrue(done.isHittable, "The real keyboard Done action must be reachable")
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "Done must dismiss the keyboard before navigating to the next form control")
    }

    @MainActor
    private func tapRecordControl(_ element: XCUIElement, in app: XCUIApplication,
                                  scrollDown: Bool = false,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        // Form materializes offscreen sections only after scrolling. Preserve the
        // bounded wait and eight real gestures, then require both existence and
        // reachability before tapping; a missing control can never pass silently.
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            if scrollDown { app.swipeDown() } else { app.swipeUp() }
        }
        if !element.exists || !element.isHittable {
            attachRecordScreenshot(app, "Record control could not be reached")
            let evidence = XCTAttachment(string: app.debugDescription)
            evidence.name = "Record control failure hierarchy"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(element.exists, "The requested record control must exist after bounded scrolling",
                      file: file, line: line)
        XCTAssertTrue(element.isHittable, "The requested record control must be reachable",
                      file: file, line: line)
        element.tap()
    }

    @MainActor
    private func attachRecordScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }

    @MainActor
    private func replaceShortNumericRecordField(_ field: XCUIElement, with value: String,
                                                in app: XCUIApplication) throws {
        try tapRecordControl(field, in: app)
        let previous = try XCTUnwrap(field.value as? String)
        XCTAssertLessThan(previous.count, 12, "This helper is only for the short English goal numeric fixtures")
        // The right edge lies after the whole short LTR value. Do not assume a
        // generic TextEditor tap places its caret at the end of multiline text.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        XCTAssertEqual(field.value as? String, value, "Replacement must enter the exact intended numeric text")
    }


    @MainActor
    func testDirectProgressAndSavedCheckInObservationRemainReachable() throws {
        let app = launchQAApplication()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        let progress = app.tabBars.buttons["Progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.isHittable)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        progress.tap()
        XCTAssertTrue(app.staticTexts["lumina.progress.empty"].waitForExistence(timeout: 5))
        let addPhoto = try recordLeafButton("lumina.progress.add-photo", in: app)
        XCTAssertTrue(addPhoto.isHittable)
        app.tabBars.buttons["Home"].tap()
        try openRecordHomeLink("Training suggestions", in: app)
        XCTAssertTrue(app.navigationBars["Adaptive Plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lumina.training.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["lumina.training.records-error"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Daily check-in", in: app)
        let note = app.textViews["lumina.checkin.new-note"]
        try tapRecordControl(note, in: app)
        note.typeText("Training observation fixture")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["lumina.checkin.new-save"], in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try openRecordHomeLink("Training suggestions", in: app)
        let scope = app.staticTexts["lumina.training.record-scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertTrue(scope.label.hasPrefix("Saved check-ins: 1. Health snapshots: 0."))
        XCTAssertFalse(app.staticTexts["lumina.training.empty"].exists)
        XCTAssertFalse(app.staticTexts["lumina.training.records-error"].exists)
    }

    @MainActor
    func testOfflineCoachAcceptsMessageAndShowsLocalReply() throws {
        let app = launchQAApplication()
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.staticTexts["Offline coaching"].waitForExistence(timeout: 5))
        let input = app.textFields["lumina.coach.message"]
        let send = try recordLeafButton("lumina.coach.send", in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
        let initialEmptyValue = try XCTUnwrap(input.value as? String)
        XCTAssertFalse(send.isEnabled)
        input.tap()
        input.typeText("How am I doing?")
        XCTAssertEqual(input.value as? String, "How am I doing?")
        XCTAssertTrue(send.isEnabled)
        XCTAssertTrue(send.isHittable)
        send.tap()
        let reply = app.staticTexts["Your logs can help you reflect on your goals. Offline coaching cannot determine physical progress or a habit's effects."]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertTrue(reply.isHittable)
        XCTAssertTrue(app.staticTexts["How am I doing?"].exists)
        XCTAssertEqual(input.value as? String, initialEmptyValue)
        XCTAssertFalse(send.isEnabled)
        let provenance = app.staticTexts.matching(identifier: "lumina.coach.reply-source")
            .matching(NSPredicate(format: "label == %@", "Offline coaching · local rules")).firstMatch
        XCTAssertTrue(provenance.waitForExistence(timeout: 5))
        XCTAssertTrue(provenance.isHittable)
        let explanation = app.staticTexts["lumina.coach.reply-source-detail"]
        XCTAssertEqual(explanation.label, "The system model is unavailable. Local guidance is available.")
        XCTAssertTrue(explanation.isHittable, "The fallback reason must remain visible separately from its source label")
        attachRecordScreenshot(app, "Offline Coach local response")
        try tapRecordControl(app.buttons["lumina.coach.insights"], in: app)
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Look for patterns"].exists)
        XCTAssertTrue(app.staticTexts["Keep conclusions tentative"].exists)
        let done = app.buttons["lumina.coach.insights.done"]
        try tapRecordControl(done, in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
        XCTAssertTrue(reply.exists)
        attachRecordScreenshot(app, "Local reflection sheet returns to Coach")
        input.tap()
        input.typeText("   ")
        XCTAssertFalse(send.isEnabled, "Whitespace alone must not send another message")
    }



    @MainActor
    func testLanguageChoiceUpdatesVisibleFlowsAndPersistsWithoutLosingDrafts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--lumina-ui-qa", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment["LUMINA_QA_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["يومياتك"].waitForExistence(timeout: 5),
                      "First launch must use the supported Arabic app/device preference")
        assertLanguageTabOrder(app, arabic: true)
        attachRecordScreenshot(app, "First launch Arabic Home and RTL tabs")

        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        try selectAppLanguage("English", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "The existing Settings screen must update without restart")
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        let backToHome = app.navigationBars["Settings"].buttons["Lumina"]
        XCTAssertTrue(backToHome.isHittable)
        backToHome.tap()
        XCTAssertTrue(app.staticTexts["Your journal"].waitForExistence(timeout: 5))
        assertLanguageTabOrder(app, arabic: false)
        attachRecordScreenshot(app, "Live English Home and LTR tabs")

        app.tabBars.buttons["Workouts"].tap()
        let draftName = app.textFields["lumina.workout.new-name"]
        XCTAssertTrue(draftName.waitForExistence(timeout: 5))
        draftName.tap()
        draftName.typeText("Unsaved language-switch fixture")
        try dismissRecordKeyboard(in: app)
        app.tabBars.buttons["Home"].tap()
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("العربية", in: app)
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["الرئيسية"].exists)
        assertLanguageTabOrder(app, arabic: true)
        attachRecordScreenshot(app, "Live Arabic Settings language control")

        app.tabBars.buttons["التمارين"].tap()
        XCTAssertTrue(draftName.waitForExistence(timeout: 5))
        XCTAssertEqual(draftName.value as? String, "Unsaved language-switch fixture",
                       "Language changes must not recreate tabs and discard drafts")
        app.tabBars.buttons["المدرب"].tap()
        let availability = app.staticTexts["lumina.coach.availability"]
        XCTAssertTrue(availability.waitForExistence(timeout: 5))
        XCTAssertEqual(availability.label, "إرشاد دون اتصال")
        let message = app.textFields["lumina.coach.message"]
        XCTAssertTrue(message.isHittable)
        XCTAssertEqual(message.label, "رسالة للمدرب")
        XCTAssertEqual(app.buttons["lumina.coach.send"].label, "إرسال الرسالة")
        message.tap()
        message.typeText("How can I record my workout?")
        let send = app.buttons["lumina.coach.send"]
        XCTAssertTrue(send.isHittable && send.isEnabled)
        send.tap()
        let arabicReply = app.staticTexts["اختر تمريناً بسيطاً يناسب طاقتك اليوم، وركّز على الحركة المتحكم بها. يمكنك تسجيل ما فعلته وكيف شعرت لمراجعته لاحقاً."]
        XCTAssertTrue(arabicReply.waitForExistence(timeout: 10),
                      "The existing UI-QA fallback must use the selected Arabic language")
        XCTAssertTrue(app.staticTexts["إرشاد دون اتصال · قواعد محلية"].exists)
        let arabicProvenance = app.staticTexts.matching(identifier: "lumina.coach.reply-source")
            .matching(NSPredicate(format: "label == %@", "إرشاد دون اتصال · قواعد محلية")).firstMatch
        XCTAssertTrue(arabicProvenance.isHittable)
        let arabicExplanation = app.staticTexts["lumina.coach.reply-source-detail"]
        XCTAssertEqual(arabicExplanation.label, "نموذج النظام غير متاح. الإرشاد المحلي متاح.")
        XCTAssertTrue(arabicExplanation.isHittable)
        let insights = app.buttons["lumina.coach.insights"]
        try tapRecordControl(insights, in: app)
        XCTAssertTrue(app.staticTexts["رؤى المدرب"].waitForExistence(timeout: 5))
        try tapRecordControl(app.buttons["lumina.coach.insights.done"], in: app)
        attachRecordScreenshot(app, "Arabic Coach labels and local-rule reply")

        app.terminate()
        // A saved app choice must win even when the next launch prefers English.
        app.launchArguments = ["--lumina-ui-qa", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["يومياتك"].waitForExistence(timeout: 5))
        assertLanguageTabOrder(app, arabic: true)
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("English", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Lumina"].tap()
        XCTAssertTrue(app.staticTexts["Your journal"].waitForExistence(timeout: 5))
        assertLanguageTabOrder(app, arabic: false)
    }

    @MainActor
    func testArabicDecimalDraftPersistsAcrossAppLanguagesOnEnglishDevice() throws {
        let app = XCUIApplication()
        // The regional decimal separator remains English while the real in-app
        // control selects Arabic. No fixture sets a numeric locale directly.
        app.launchArguments = ["--lumina-ui-qa", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LUMINA_QA_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Your journal"].waitForExistence(timeout: 5))
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try selectAppLanguage("العربية", in: app)
        app.tabBars.buttons["التمارين"].tap()
        let name = app.textFields["lumina.workout.new-name"]
        try tapRecordControl(name, in: app)
        name.typeText("Arabic decimal fixture")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["إضافة تمرين"], in: app)
        let exerciseFields = app.textFields.matching(NSPredicate(format: "label == %@ AND identifier != %@",
            "اسم التمرين", "lumina.workout.new-name"))
        XCTAssertTrue(exerciseFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(exerciseFields.count, 1, "The exercise field must be distinct from the identically named workout field")
        let exercise = exerciseFields.element(boundBy: 0)
        try tapRecordControl(exercise, in: app)
        exercise.typeText("Decimal squat")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["إضافة مجموعة"], in: app)
        let arabicWeight = app.textFields["الوزن بالكيلوغرام في Decimal squat"]
        try tapRecordControl(arabicWeight, in: app)
        arabicWeight.typeText("١٢٫٥")
        XCTAssertEqual(arabicWeight.value as? String, "١٢٫٥")
        try dismissRecordKeyboard(in: app)

        // A live language change preserves the exact unsaved text, and Save
        // must parse it even after the app switches to the other decimal mark.
        app.tabBars.buttons["الرئيسية"].tap()
        XCTAssertTrue(app.navigationBars["الإعدادات"].waitForExistence(timeout: 5))
        try selectAppLanguage("English", in: app)
        app.tabBars.buttons["Workouts"].tap()
        let englishWeight = app.textFields["Weight in kilograms for Decimal squat"]
        try tapRecordControl(englishWeight, in: app, scrollDown: true)
        XCTAssertEqual(englishWeight.value as? String, "١٢٫٥")
        try dismissRecordKeyboard(in: app)
        try tapRecordControl(app.buttons["lumina.workout.new-save"], in: app)
        XCTAssertTrue(app.alerts["Workout saved!"].waitForExistence(timeout: 5),
                      "The production Save path must accept the preserved Arabic decimal")
        app.alerts.buttons["OK"].tap()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        try selectAppLanguage("العربية", in: app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["يومياتك"].waitForExistence(timeout: 5))
        app.tabBars.buttons["التمارين"].tap()
        try tapRecordControl(app.buttons["lumina.workout.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Arabic decimal fixture"], in: app)
        let savedWeight = app.textFields["الوزن بالكيلوغرام في Decimal squat"]
        try tapRecordControl(savedWeight, in: app)
        XCTAssertEqual(savedWeight.value as? String, "12٫5",
                       "Reopened numeric fields must format the saved value in the selected app locale")
        attachRecordScreenshot(app, "Arabic decimal retained and formatted on English-region phone")
    }

    @MainActor
    private func selectAppLanguage(_ label: String, in app: XCUIApplication) throws {
        let picker = app.segmentedControls["lumina.language-picker"]
        let choice = picker.buttons[label]
        try tapRecordControl(choice, in: app)
        let arabic = label == "العربية"
        let title = arabic ? "الإعدادات" : "Settings"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5),
                      "The existing Settings screen must display the chosen language")
        // Direction changes re-layout the Form, so its virtualized rows can
        // move offscreen. Re-reveal the actual picker without tapping again.
        // Retain the selected-state requirement after that real traversal.
        for _ in 0..<8 {
            if choice.exists && choice.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.exists && picker.isHittable)
        XCTAssertTrue(choice.exists && choice.isHittable)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The real language control must show the selected choice")
        let other = picker.buttons[arabic ? "English" : "العربية"]
        XCTAssertTrue(other.exists && other.isHittable)
        XCTAssertFalse(other.isSelected, "The other native segment must be unselected")
        XCTAssertEqual(picker.buttons.count, 2)
        let english = picker.buttons["English"]
        let arabicChoice = picker.buttons["العربية"]
        XCTAssertEqual(english.label, "English")
        XCTAssertEqual(arabicChoice.label, "العربية")
        // Retain the real AX operands before geometry assertions can stop
        // this case. No screenshot or frame is synthesized or transformed.
        let bar = app.navigationBars[title]
        let back = bar.buttons["Lumina"]
        let containingCells = app.cells.containing(.segmentedControl, identifier: "lumina.language-picker")
        let cell = containingCells.element(boundBy: 0)
        func geometry(_ element: XCUIElement) -> [String: Any] {
            let frame = element.frame
            return ["identifier": element.identifier, "label": element.label,
                    "elementType": element.elementType.rawValue,
                    "exists": element.exists, "hittable": element.isHittable,
                    "selected": element.isSelected,
                    "x": Double(frame.origin.x), "y": Double(frame.origin.y),
                    "width": Double(frame.size.width), "height": Double(frame.size.height),
                    "minX": Double(frame.minX), "maxX": Double(frame.maxX),
                    "minY": Double(frame.minY), "maxY": Double(frame.maxY)]
        }
        let operands: [String: Any] = ["schemaVersion": 1,
            "purpose": "LIVE_LANGUAGE_SELECTION_GEOMETRY_AND_RETAINED_SCREEN",
            "language": arabic ? "ar" : "en", "requestedChoice": label,
            "picker": geometry(picker), "English": geometry(english),
            "Arabic": geometry(arabicChoice), "chosen": geometry(choice),
            "opposite": geometry(other), "app": geometry(app),
            "navigationBar": geometry(bar), "Back": geometry(back),
            "containingCellCount": containingCells.count,
            "containingCell": containingCells.count == 1 ? geometry(cell) : [:]]
        let numericData = try JSONSerialization.data(withJSONObject: operands, options: [.sortedKeys])
        let numericEvidence = XCTAttachment(data: numericData, uniformTypeIdentifier: "public.json")
        numericEvidence.name = "Exact observed pre-assertion language geometry operands"
        numericEvidence.lifetime = .keepAlways
        add(numericEvidence)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Unmodified Settings AX before geometry assertions"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let evidence = XCTAttachment(string: "language=\(arabic ? "ar" : "en") title=\(title) chosenSelected=\(choice.isSelected) otherSelected=\(other.isSelected) picker=\(picker.frame) English=\(english.frame) Arabic=\(arabicChoice.frame) Back=\(back.frame)")
        evidence.name = "Observed Settings language selection and geometry"
        evidence.lifetime = .keepAlways
        add(evidence)
        attachRecordScreenshot(app, "Settings after live language change - \(title)")
        XCTAssertGreaterThan(english.frame.width, 0)
        XCTAssertGreaterThan(arabicChoice.frame.width, 0)
        // Original native v6.1 diagnostic: parent height 31pt, both native
        // segment AX hit rectangles 32pt with the same top. The only observed
        // overhang was 1pt below the parent; no top or horizontal tolerance
        // is allowed. Require the real containing Form cell and screen too.
        XCTAssertEqual(containingCells.count, 1)
        XCTAssertTrue(cell.exists)
        XCTAssertTrue(cell.frame.contains(picker.frame))
        XCTAssertTrue(app.frame.contains(cell.frame))
        let leadingInPixels = arabic ? arabicChoice : english
        let trailingInPixels = arabic ? english : arabicChoice
        XCTAssertEqual(leadingInPixels.frame.minX, picker.frame.minX)
        XCTAssertEqual(leadingInPixels.frame.maxX, trailingInPixels.frame.minX)
        XCTAssertEqual(trailingInPixels.frame.maxX, picker.frame.maxX)
        for segment in [english, arabicChoice] {
            XCTAssertEqual(segment.frame.minY, picker.frame.minY)
            let bottomOverhang = segment.frame.maxY - picker.frame.maxY
            XCTAssertGreaterThanOrEqual(bottomOverhang, 0)
            XCTAssertLessThanOrEqual(bottomOverhang, 1,
                                     "Only the observed one-point native bottom hit-rectangle extension is admitted")
            XCTAssertTrue(cell.frame.contains(segment.frame))
            XCTAssertTrue(app.frame.contains(segment.frame))
        }
        XCTAssertTrue(app.frame.contains(picker.frame))
        XCTAssertTrue(back.exists && back.isHittable)
        XCTAssertEqual(back.label, arabic ? "العودة إلى الرئيسية" : "Back to Home")
        if arabic {
            XCTAssertGreaterThan(english.frame.midX, arabicChoice.frame.midX,
                                 "Arabic must mirror the actual language-segment order")
            XCTAssertGreaterThan(back.frame.midX, bar.frame.midX,
                                 "Arabic Settings must place Back on its leading edge")
        } else {
            XCTAssertLessThan(english.frame.midX, arabicChoice.frame.midX,
                              "English must restore the actual language-segment order")
            XCTAssertLessThan(back.frame.midX, bar.frame.midX,
                              "English Settings must place Back on its leading edge")
        }
        try assertReadableEnglishSegment(english)
    }

    @MainActor
    private func assertReadableEnglishSegment(_ english: XCUIElement) throws {
        // AX labels and bounding boxes do not detect horizontally mirrored
        // glyphs. Read the real button pixels with the built-in Vision API;
        // no generated fixture, network, model installation or expected-text
        // hint is supplied to recognition. Preserve the original screenshot.
        let shot = english.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "Unmodified English language-segment pixels"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        } catch {
            let evidence = XCTAttachment(string: "orientation=up revision=\(request.revision) error=\(error)")
            evidence.name = "Native language-segment OCR error"
            evidence.lifetime = .keepAlways
            add(evidence)
            throw error
        }
        let observations = request.results ?? []
        let readings = observations.compactMap { $0.topCandidates(1).first?.string }
        let rows = observations.map { observation in
            "text=\(observation.topCandidates(1).first?.string ?? "") confidence=\(observation.topCandidates(1).first?.confidence ?? 0) normalizedBox=\(observation.boundingBox)"
        }
        let evidence = XCTAttachment(string: "orientation=up revision=\(request.revision) errors=none\n" + rows.joined(separator: "\n"))
        evidence.name = "Native OCR of English segment, without text correction"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTAssertTrue(readings.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "English" },
                      "The actual control pixels must produce the exact English label")
        // OCR may normalize an image, so it supplements the native geometry
        // checks and retained full-screen visual review; it does not certify
        // that every Form glyph is correctly oriented on its own.
    }

    @MainActor
    private func assertLanguageTabOrder(_ app: XCUIApplication, arabic: Bool,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let home = app.tabBars.buttons[arabic ? "الرئيسية" : "Home"]
        let progress = app.tabBars.buttons[arabic ? "التقدم" : "Progress"]
        XCTAssertTrue(home.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(progress.exists && home.isHittable && progress.isHittable, file: file, line: line)
        XCTAssertGreaterThan(home.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(progress.frame.width, 0, file: file, line: line)
        if arabic {
            XCTAssertGreaterThan(home.frame.midX, progress.frame.midX,
                                 "Arabic must mirror the actual tab order", file: file, line: line)
        } else {
            XCTAssertLessThan(home.frame.midX, progress.frame.midX,
                              "English must restore the actual tab order", file: file, line: line)
        }
        let evidence = XCTAttachment(string: "language=\(arabic ? "ar" : "en") home=\(home.frame) progress=\(progress.frame)")
        evidence.name = "Observed language and tab frames"
        evidence.lifetime = .keepAlways
        add(evidence)
    }


    @MainActor
    func testRecoveryPreviewFixtureConfirmationReopenAndPickerCancelPaths() throws {
        let app = launchQAApplication(additionalArguments: ["--lumina-qa-recovery-fixture"])
        XCTAssertTrue(app.staticTexts["Meals logged today: 0"].waitForExistence(timeout: 15))
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try tapRecordControl(app.buttons["lumina.restore.choose"], in: app)
        // This is the actual system picker, canceled without selecting a file.
        let pickerCancel = app.buttons["Cancel"]
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10))
        XCTAssertTrue(pickerCancel.isHittable)
        attachRecordScreenshot(app, "Actual restore file picker before Cancel")
        pickerCancel.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Restore journal"].exists)

        // Only the file-selection boundary is substituted for this isolated
        // fixture. Production export, copy, untrusted decode, preview and final
        // transactional import run unchanged. No destination records are seeded.
        try tapRecordControl(app.buttons["lumina.restore.qa-fixture"], in: app)
        XCTAssertTrue(app.navigationBars["Restore journal"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Records: 2"].exists)
        let confirm = try recordLeafButton("lumina.restore.confirm", in: app)
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable)
        attachRecordScreenshot(app, "Validated recovery preview before explicit confirmation")
        try tapRecordControl(try recordLeafButton("lumina.restore.cancel", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Lumina"].tap()
        XCTAssertTrue(app.staticTexts["Meals logged today: 0"].waitForExistence(timeout: 5),
                      "Canceling a validated preview must leave the journal empty")
        try tapRecordControl(app.buttons["lumina.settings"], in: app)
        try tapRecordControl(app.buttons["lumina.restore.qa-fixture"], in: app)
        XCTAssertTrue(app.navigationBars["Restore journal"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Records: 2"].exists)
        try tapRecordControl(try recordLeafButton("lumina.restore.confirm", in: app), in: app)
        XCTAssertTrue(app.staticTexts["Restored 2 records."].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Restore journal"].exists)
        attachRecordScreenshot(app, "Explicit two-record restore completed")
        try tapRecordControl(app.buttons["lumina.backup.export"], in: app)
        let exportSave = app.buttons["Save"]
        XCTAssertTrue(exportSave.waitForExistence(timeout: 30),
                      "The prepared backup must open the real system exporter")
        let exportCancel = app.buttons["Cancel"]
        if !exportCancel.exists {
            // The system can reopen On My iPhone, where Browse leads to the
            // root Cancel action. This is one observed native navigation step.
            let browse = app.buttons["Browse"]
            XCTAssertTrue(browse.waitForExistence(timeout: 5))
            XCTAssertTrue(browse.isHittable)
            attachRecordScreenshot(app, "Actual prepared backup destination before Browse")
            browse.tap()
        }
        XCTAssertTrue(exportCancel.waitForExistence(timeout: 30))
        XCTAssertTrue(exportCancel.isHittable)
        attachRecordScreenshot(app, "Actual prepared backup file exporter before Cancel")
        exportCancel.tap()
        let exporterDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: exportSave)
        XCTAssertEqual(XCTWaiter.wait(for: [exporterDismissed], timeout: 5), .completed)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lumina.backup.export"].isEnabled)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "lumina.backup.error").count, 0)
        try tapRecordControl(app.buttons["lumina.restore.qa-fixture"], in: app)
        XCTAssertTrue(app.navigationBars["Restore journal"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Restore is available only when your local journal is empty. Existing records have not been changed."].waitForExistence(timeout: 5))
        XCTAssertFalse(try recordLeafButton("lumina.restore.confirm", in: app).isEnabled,
                       "A read-only preview must not offer to overwrite the existing journal")
        XCTAssertTrue(app.staticTexts["Previewing this backup does not change your existing records. You do not need to delete anything to inspect it."].exists)
        attachRecordScreenshot(app, "Populated journal can inspect a backup while Restore remains disabled")
        try tapRecordControl(try recordLeafButton("lumina.restore.cancel", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Restore journal"].exists)
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Meals logged today: 1"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Nutrition"].tap()
        try tapRecordControl(app.buttons["lumina.meal.history"], in: app)
        try tapRecordControl(app.collectionViews.staticTexts["Recovery fixture meal"], in: app)
        XCTAssertTrue(app.navigationBars["Saved meal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["lumina.meal.record-notes"].value as? String,
                       "Reviewable recovery fixture note")
        XCTAssertEqual(Double(app.textFields["Protein in grams"].value as? String ?? ""), 42)
        attachRecordScreenshot(app, "Restored meal fields after real app relaunch")
    }
}
