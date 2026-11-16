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
        XCTAssertTrue(app.navigationBars["Lumina"].waitForExistence(timeout: 15))
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-home-audit.png")
        try app.screenshot().pngRepresentation.write(to: imageURL)
        print("HOME QA SCREENSHOT:", imageURL.path)
        for position in 0..<3 {
            let auditURL = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-audit-position-\(position).png")
            try app.screenshot().pngRepresentation.write(to: auditURL)
            print("AUDIT POSITION:", position, auditURL.path)
            try app.performAccessibilityAudit(for: .contrast) { issue in
                if let element = issue.element, !element.isHittable {
                    print("DEFERRED OFFSCREEN AUDIT:", issue.compactDescription, element.label)
                    return true
                }
                print("AUDIT ISSUE:", issue.compactDescription, issue.detailedDescription,
                      issue.element?.debugDescription ?? "No element")
                return false
            }
            app.swipeUp()
        }
        // Dynamic Type audits resize the app; keep contrast checks in a separate pass.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["lumina.qa-store"].waitForExistence(timeout: 15))
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast))
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
