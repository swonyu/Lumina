import XCTest
import Foundation
import UIKit

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

        app.buttons["Health permissions"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["Health access is unavailable in this build. Your existing records remain available."].exists)
        app.alerts.buttons["OK"].tap()

        app.buttons["Export database backup"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        if !app.buttons["Cancel"].exists, app.buttons["Browse"].exists {
            app.buttons["Browse"].tap()
        }
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
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
                let target = outstanding[0]
                try revealHomeAuditLeaf(target, in: app, ledger: ledger)
                try auditHomeContrast(app, leaves: leaves, ledger: ledger,
                    name: "Coverage pass \(attempt) for \(target.key)")
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
        var summary: [String: Any] {
            ["required_leaf_count": 20, "covered": covered.sorted(),
             "unresolved": pending.sorted(), "full_audit_count": audits,
             "findings": findings, "movements": movements]
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
        ledger.audits += 1
        passed = true
    }

    @MainActor
    private func revealHomeAuditLeaf(_ leaf: HomeAuditLeaf, in app: XCUIApplication,
                                     ledger: HomeAuditLedger) throws {
        for gesture in 0..<10 {
            let viewport = try homeAuditViewport(app)
            let element = try resolveHomeAuditLeaf(leaf, in: app)
            let frame = element.frame
            if viewport.contains(frame) && element.isHittable { return }
            try requireHomeAudit(frame.width <= viewport.width && frame.height <= viewport.height
                && frame.minX >= viewport.minX && frame.maxX <= viewport.maxX,
                "Home leaf cannot fit the unobscured viewport: \(leaf.key)")
            try requireHomeAudit(!viewport.contains(frame),
                "Home leaf is geometrically visible but not hittable: \(leaf.key)")
            let difference = frame.midY - viewport.midY
            let travel = min(max(abs(difference), viewport.height * 0.15), viewport.height * 0.45)
            let direction: CGFloat = difference > 0 ? 1 : -1
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                dy: viewport.midY - app.frame.minY + direction * travel / 2))
            let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                dy: viewport.midY - app.frame.minY - direction * travel / 2))
            ledger.movements.append(["target": leaf.key, "gesture": gesture,
                "viewport": homeAuditFrame(viewport), "element_before": homeAuditElement(element),
                "vertical_travel": String(describing: -direction * travel)])
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let finalViewport = try homeAuditViewport(app)
        let finalElement = try resolveHomeAuditLeaf(leaf, in: app)
        try requireHomeAudit(finalViewport.contains(finalElement.frame) && finalElement.isHittable,
            "Bounded scrolling did not reveal Home leaf: \(leaf.key)")
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

}
