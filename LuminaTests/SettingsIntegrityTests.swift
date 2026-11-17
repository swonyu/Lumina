import Foundation
import SwiftData
import Testing
@testable import Lumina

@MainActor
struct SettingsIntegrityTests {
    @Test func turningOffDuringPermissionCannotReenableTheReminder() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.holdAuthorization = true
        let enabling = fixture.coordinator.setEnabled(true)
        await fixture.client.waitForAuthorizationCount(1)
        let disabling = fixture.coordinator.setEnabled(false)
        #expect(!fixture.coordinator.isEnabled)
        #expect(!fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
        fixture.client.finishAuthorization(0, granted: true)
        await enabling.value
        await disabling.value
        #expect(fixture.client.scheduleCalls.isEmpty && fixture.client.pending.isEmpty)
        #expect(!fixture.coordinator.isEnabled && !fixture.coordinator.isUpdating)
        #expect(fixture.coordinator.errorMessage == nil)
    }

    @Test func anAddFinishingAfterOffRemovesItsOwnRequest() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.holdScheduling = true
        let enabling = fixture.coordinator.setEnabled(true)
        await fixture.client.waitForScheduleCount(1)
        let identifier = try #require(fixture.client.scheduleCalls.first)
        let disabling = fixture.coordinator.setEnabled(false)
        fixture.client.finishSchedule(identifier)
        await enabling.value
        await disabling.value
        #expect(!fixture.client.pending.contains(identifier))
        #expect(!fixture.coordinator.isEnabled)
        #expect(!fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
    }

    @Test func staleAddCleanupCannotRemoveANewerEnabledReminder() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.holdScheduling = true
        let first = fixture.coordinator.setEnabled(true)
        await fixture.client.waitForScheduleCount(1)
        let firstID = try #require(fixture.client.scheduleCalls.first)
        await fixture.coordinator.setEnabled(false).value
        fixture.client.holdScheduling = false
        await fixture.coordinator.setEnabled(true).value
        let latestID = try #require(fixture.client.scheduleCalls.last)
        #expect(firstID != latestID)
        #expect(fixture.client.pending == [latestID])
        fixture.client.finishSchedule(firstID)
        await first.value
        #expect(fixture.client.pending == [latestID])
        #expect(fixture.coordinator.isEnabled && !fixture.coordinator.isUpdating)
        #expect(fixture.preferences.string(forKey: WeeklyReminderCoordinator.requestKey) == latestID)
    }

    @Test func deletingTheJournalInvalidatesPendingReminderPermission() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        let schema = Schema(LuminaApp.modelTypes)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let model = LuminaViewModel(modelContext: container.mainContext, weeklyReminders: fixture.coordinator)
        #expect(model.saveRecord(MealLog(mealName: "Delete reminder fixture")))
        fixture.client.holdAuthorization = true
        let enabling = fixture.coordinator.setEnabled(true)
        await fixture.client.waitForAuthorizationCount(1)
        try model.deleteAllLocalRecords()
        #expect(!fixture.coordinator.isEnabled)
        fixture.client.finishAuthorization(0, granted: true)
        await enabling.value
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 0)
        #expect(fixture.client.scheduleCalls.isEmpty && fixture.client.pending.isEmpty)
        #expect(!fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
    }

    @Test func lateStartupCannotSupersedeAUserPermissionRequest() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.holdAuthorization = true
        let enabling = fixture.coordinator.setEnabled(true)
        await fixture.client.waitForAuthorizationCount(1)
        await fixture.coordinator.refreshWithoutPrompt().value
        #expect(fixture.client.authorizationRequests == [true])
        #expect(fixture.coordinator.isEnabled && fixture.coordinator.isUpdating)
        fixture.client.finishAuthorization(0, granted: true)
        await enabling.value
        #expect(fixture.client.pending.count == 1 && fixture.coordinator.isEnabled)
    }

    @Test func startupUsesTheInjectedPreferenceAndReconcilesOnlyItsRequests() async throws {
        let fixture = try ReminderFixture(enabled: true)
        defer { fixture.clear() }
        let prior = WeeklyReminderCoordinator.identifierPrefix + UUID().uuidString
        fixture.client.pending = [WeeklyReminderCoordinator.legacyIdentifier, prior, "unrelated-fixture"]
        await fixture.coordinator.refreshWithoutPrompt().value
        let current = try #require(fixture.client.scheduleCalls.first)
        #expect(fixture.client.authorizationRequests == [false])
        #expect(fixture.client.pending == [current, "unrelated-fixture"])
        #expect(fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
        #expect(fixture.preferences.string(forKey: WeeklyReminderCoordinator.requestKey) == current)
        await fixture.coordinator.setEnabled(false).value
        #expect(fixture.client.pending == ["unrelated-fixture"])
    }

    @Test func deniedAuthorizationLeavesAnAccurateDisabledPreference() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.authorized = false
        await fixture.coordinator.setEnabled(true).value
        #expect(!fixture.coordinator.isEnabled && !fixture.coordinator.isUpdating)
        #expect(!fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
        #expect(fixture.client.scheduleCalls.isEmpty)
        #expect(fixture.coordinator.errorMessage?.contains("iOS Settings") == true)
    }

    @Test func failedSchedulingDoesNotLeaveAFalseEnabledState() async throws {
        let fixture = try ReminderFixture()
        defer { fixture.clear() }
        fixture.client.scheduleError = CocoaError(.fileWriteUnknown)
        await fixture.coordinator.setEnabled(true).value
        #expect(!fixture.coordinator.isEnabled && !fixture.coordinator.isUpdating)
        #expect(!fixture.preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
        #expect(fixture.preferences.string(forKey: WeeklyReminderCoordinator.requestKey) == nil)
        #expect(fixture.client.pending.isEmpty)
        #expect(fixture.coordinator.errorMessage?.contains("Could not enable") == true)
    }

    @Test func trainingObservationsUseTheLatestPersistedCheckIns() throws {
        let schema = Schema(LuminaApp.modelTypes)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<17 {
            context.insert(DailyCheckIn(date: start.addingTimeInterval(Double(index) * 86_400),
                energyLevel: index < 3 ? 2 : 5, sorenessLevel: 5, sleepQuality: 5,
                stressLevel: 5, mood: .okay))
        }
        try context.save()
        let latest = try context.fetch(AdaptivePlanLogic.checkInDescriptor)
        #expect(latest.count == 14)
        #expect(latest.first?.date == start.addingTimeInterval(16 * 86_400))
        #expect(latest.last?.date == start.addingTimeInterval(3 * 86_400))
        #expect(AdaptivePlanLogic.shouldAdjustPlan(recentCheckIns: latest, recentSnapshots: []) == nil)
        for entry in latest.prefix(3) { entry.energyLevel = 2 }
        try context.save()
        let current = try context.fetch(AdaptivePlanLogic.checkInDescriptor)
        let observation = try #require(AdaptivePlanLogic.shouldAdjustPlan(recentCheckIns: current, recentSnapshots: []))
        #expect(observation.contains("energy ratings below 4/10"))
        #expect(observation.contains("do not establish your current readiness"))
    }

    @Test func healthObservationWindowDoesNotUseOlderExcludedSnapshots() throws {
        let schema = Schema(LuminaApp.modelTypes)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<16 {
            let snapshot = HealthSnapshot(date: start.addingTimeInterval(Double(index) * 86_400))
            snapshot.sleepHours = index < 2 ? 4 : 8
            context.insert(snapshot)
        }
        try context.save()
        let latest = try context.fetch(AdaptivePlanLogic.snapshotDescriptor)
        #expect(latest.count == 14)
        #expect(latest.last?.date == start.addingTimeInterval(2 * 86_400))
        #expect(AdaptivePlanLogic.shouldAdjustPlan(recentCheckIns: [], recentSnapshots: latest) == nil)
        for snapshot in latest.prefix(2) { snapshot.sleepHours = 4 }
        try context.save()
        let current = try context.fetch(AdaptivePlanLogic.snapshotDescriptor)
        let observation = try #require(AdaptivePlanLogic.shouldAdjustPlan(recentCheckIns: [], recentSnapshots: current))
        #expect(observation.contains("sleep entries below 6 hours"))
        #expect(observation.contains("do not establish your current readiness"))
    }
}

@MainActor
private struct ReminderFixture {
    let name: String
    let preferences: UserDefaults
    let client: ControlledReminderClient
    let coordinator: WeeklyReminderCoordinator

    init(enabled: Bool = false) throws {
        let name = "Lumina-reminder-test-" + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: name))
        preferences.set(enabled, forKey: WeeklyReminderCoordinator.enabledKey)
        let client = ControlledReminderClient()
        self.name = name
        self.preferences = preferences
        self.client = client
        coordinator = WeeklyReminderCoordinator(preferences: preferences, client: client)
    }

    func clear() { preferences.removePersistentDomain(forName: name) }
}

/// Controlled noncooperative completions prove stale-callback behavior without
/// requesting system permission, delivering notifications or waiting on clocks.
@MainActor
private final class ControlledReminderClient: WeeklyReminderClient {
    var pending: Set<String> = []
    var authorized = true
    var holdAuthorization = false
    var holdScheduling = false
    var scheduleError: (any Error)?
    private(set) var authorizationRequests: [Bool] = []
    private(set) var scheduleCalls: [String] = []
    private var authorizations: [Int: CheckedContinuation<Bool, any Error>] = [:]
    private var schedules: [String: CheckedContinuation<Void, any Error>] = [:]
    private var authorizationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var scheduleWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func pendingIdentifiers() async -> [String] { pending.sorted() }

    func isAuthorized(requestIfNeeded: Bool) async throws -> Bool {
        let index = authorizationRequests.count
        authorizationRequests.append(requestIfNeeded)
        if !holdAuthorization { return authorized }
        return try await withCheckedThrowingContinuation { continuation in
            authorizations[index] = continuation
            let ready = authorizationWaiters.filter { $0.0 <= authorizationRequests.count }
            authorizationWaiters.removeAll { $0.0 <= authorizationRequests.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func schedule(identifier: String) async throws {
        scheduleCalls.append(identifier)
        if let scheduleError { throw scheduleError }
        if !holdScheduling { pending.insert(identifier); return }
        try await withCheckedThrowingContinuation { continuation in
            schedules[identifier] = continuation
            let ready = scheduleWaiters.filter { $0.0 <= scheduleCalls.count }
            scheduleWaiters.removeAll { $0.0 <= scheduleCalls.count }
            for (_, waiter) in ready { waiter.resume() }
        }
    }

    func remove(identifiers: [String]) { pending.subtract(identifiers) }

    func waitForAuthorizationCount(_ count: Int) async {
        if authorizationRequests.count >= count { return }
        await withCheckedContinuation { authorizationWaiters.append((count, $0)) }
    }

    func waitForScheduleCount(_ count: Int) async {
        if scheduleCalls.count >= count { return }
        await withCheckedContinuation { scheduleWaiters.append((count, $0)) }
    }

    func finishAuthorization(_ index: Int, granted: Bool) {
        precondition(authorizations[index] != nil)
        authorizations.removeValue(forKey: index)?.resume(returning: granted)
    }

    func finishSchedule(_ identifier: String) {
        precondition(schedules[identifier] != nil)
        pending.insert(identifier)
        schedules.removeValue(forKey: identifier)?.resume()
    }
}
