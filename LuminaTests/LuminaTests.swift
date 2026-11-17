//
//  LuminaTests.swift
//  LuminaTests
//
//  Created by saleh alayed on 10/12/1447 AH.
//

import Foundation
import Testing
import SwiftData
@testable import Lumina

struct LuminaTests {
    @MainActor
    @Test func offlineStoragePreservesDefaultLocation() throws {
        let schema = Schema(LuminaApp.modelTypes)
        let previous = ModelConfiguration(schema: schema)
        let offline = try LuminaApp.localStorageConfiguration(schema: schema)
        #expect(offline.url == previous.url)
        #expect(offline.groupAppContainerIdentifier == previous.groupAppContainerIdentifier)
        #expect(offline.cloudKitContainerIdentifier == nil)
        #expect(offline.allowsSave)
    }

    @MainActor
    @Test func launchPreservesRecordsWithoutInventingSamples() async throws {
        let schema = Schema([Item.self, UserProfile.self, BodyMetric.self, HealthSnapshot.self,
            Milestone.self, ProgressPhoto.self, Streak.self, MealLog.self, DailyCheckIn.self,
            WorkoutLog.self, JournalEntry.self, CoachMemoryEntry.self, Goal.self, Habit.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let model = LuminaViewModel(modelContext: container.mainContext)
        await model.bootstrapAfterLaunch()
        #expect(model.currentUser == nil)
        #expect(model.recentHealthSnapshots.isEmpty)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DailyCheckIn>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WorkoutLog>()) == 0)

        let meal = MealLog(mealName: "Retention check", calories: 450, notes: "Keep this record")
        container.mainContext.insert(meal)
        try container.mainContext.save()
        let savedID = meal.id
        let nextContext = ModelContext(container)
        await LuminaViewModel(modelContext: nextContext).bootstrapAfterLaunch()
        let savedMeals = try nextContext.fetch(FetchDescriptor<MealLog>())
        #expect(savedMeals.count == 1)
        #expect(savedMeals.first?.id == savedID)
        #expect(savedMeals.first?.notes == "Keep this record")
        let habit = Habit(name: "Fixture habit")
        #expect(model.saveRecord(habit))
        habit.toggleCompletion()
        try container.mainContext.save()
        await model.recordHabitCompletion(habit: habit)
        #expect(model.persistedCoachMemory.first?.content.hasPrefix("Completed habit") == true)
        habit.toggleCompletion()
        try container.mainContext.save()
        await model.recordHabitCompletion(habit: habit)
        #expect(model.persistedCoachMemory.first?.content.hasPrefix("Undid today's completion") == true)
    }


    @MainActor
    @Test func streaksUseConsecutiveDatesAndResetAfterGaps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -3, to: now)!
        #expect(LuminaViewModel.checkInStreak(dates: [], now: now, calendar: calendar) == 0)
        #expect(LuminaViewModel.checkInStreak(dates: [now, now, yesterday, older], now: now, calendar: calendar) == 2)
        #expect(LuminaViewModel.checkInStreak(dates: [older], now: now, calendar: calendar) == 0)
        let habit = Habit(name: "Fixture")
        habit.currentStreak = 7
        habit.lastCompletedDate = older
        habit.toggleCompletion(now: now, calendar: calendar)
        #expect(habit.currentStreak == 1)
        habit.toggleCompletion(now: now, calendar: calendar)
        #expect(habit.currentStreak == 7 && habit.lastCompletedDate == older && habit.totalCompletions == 0)
        habit.lastCompletedDate = yesterday
        habit.currentStreak = 3
        habit.toggleCompletion(now: now, calendar: calendar)
        #expect(habit.currentStreak == 4)
    }

    @MainActor
    @Test func suggestedHabitPersistsWithoutInventingACompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(LuminaApp.modelTypes)
        let config = ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("habits.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        weak var retainedModel: LuminaViewModel?
        do {
            let model = LuminaViewModel(modelContext: container.mainContext)
            retainedModel = model
            #expect(model.addCoachSuggestedHabit(name: "  Evening walk  ",
                reason: "Selected from general habit ideas"))
            let nextContext = ModelContext(container)
            let habits = try nextContext.fetch(FetchDescriptor<Habit>())
            let habit = try #require(habits.first)
            #expect(habits.count == 1)
            #expect(habit.name == "Evening walk")
            #expect(habit.coachNotes == "Selected from general habit ideas")
            #expect(habit.lastCompletedDate == nil)
            #expect(habit.totalCompletions == 0 && habit.currentStreak == 0)
            #expect(model.justAddedCoachHabit == habit.name)
            #expect(!model.addCoachSuggestedHabit(name: "EVENING WALK"))
            #expect(try nextContext.fetchCount(FetchDescriptor<Habit>()) == 1)
        }
        // Delayed UI feedback must not keep this fixture model alive past cleanup.
        #expect(retainedModel == nil)
    }

    @MainActor
    @Test func trainingSuggestionDescribesTheAvailableMeasurements() throws {
        let snapshots = (0..<2).map { _ in
            let snapshot = HealthSnapshot()
            snapshot.heartRateVariability = 40
            return snapshot
        }
        let suggestion = try #require(AdaptivePlanLogic.shouldAdjustPlan(
            recentCheckIns: [], recentSnapshots: snapshots))
        #expect(suggestion.contains("HRV"))
        #expect(!suggestion.lowercased().contains("energy"))
        #expect(!suggestion.lowercased().contains("sleep"))
        #expect(AdaptivePlanLogic.shouldAdjustPlan(recentCheckIns: [], recentSnapshots: []) == nil)
    }

    @MainActor
    @Test func databaseBackupRoundTripsRecordsAndDeletionIsIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(LuminaApp.modelTypes)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("source.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let model = LuminaViewModel(modelContext: context)
        let meal = MealLog(mealName: "Backup fixture", notes: "Keep exact notes", photoData: Data([1, 2, 3]))
        #expect(model.saveRecord(meal))
        context.insert(ProgressPhoto(photoData: Data([4, 5, 6])))
        context.insert(WorkoutLog(workoutName: "Fixture workout"))
        context.insert(JournalEntry(content: "Fixture journal"))
        context.insert(Habit(name: "Fixture habit"))
        context.insert(Goal(name: "Fixture goal", targetValue: 1, unit: "completion", category: "general"))
        context.insert(HealthSnapshot())
        context.insert(CoachMemoryEntry(type: .reflection, content: "Fixture memory"))
        context.insert(Item())
        context.insert(BodyMetric(weightKg: 70))
        context.insert(Milestone(title: "Fixture", description: "Fixture", category: .consistency))
        context.insert(Streak(type: .checkIn))
        context.insert(DailyCheckIn(energyLevel: 5, sorenessLevel: 3, sleepQuality: 6, stressLevel: 4, mood: .good, didTrain: false))
        let user = UserProfile(name: "Fixture", age: 30, gender: .other, heightCm: 170, currentWeightKg: 70,
            experienceLevel: .beginner, primaryGoal: .generalHealth, workoutDaysPerWeek: 2, equipmentAccess: .none)
        context.insert(user)
        meal.owner = user
        try context.fetch(FetchDescriptor<Goal>()).first?.owner = user
        try context.save()
        let backupURL = directory.appendingPathComponent("backup.sqlite")
        try model.exportDatabase().write(to: backupURL)
        let restored = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: backupURL, cloudKitDatabase: .none)])
        let restoredMeals = try restored.mainContext.fetch(FetchDescriptor<MealLog>())
        #expect(restoredMeals.first?.id == meal.id)
        #expect(restoredMeals.first?.notes == "Keep exact notes")
        #expect(restoredMeals.first?.photoData == Data([1, 2, 3]))
        #expect(try restored.mainContext.fetch(FetchDescriptor<ProgressPhoto>()).first?.photoData == Data([4, 5, 6]))
        let readOnlyURL = directory.appendingPathComponent("read-only.sqlite")
        try model.exportDatabase().write(to: readOnlyURL)
        let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: readOnlyURL, allowsSave: false, cloudKitDatabase: .none)])
        let readOnlyModel = LuminaViewModel(modelContext: readOnly.mainContext)
        let beforeFailure = try readOnly.mainContext.fetch(FetchDescriptor<MealLog>())
        #expect(!readOnlyModel.saveRecord(MealLog(mealName: "Must fail")))
        #expect(readOnlyModel.errorMessage != nil)
        let afterFailure = try readOnly.mainContext.fetch(FetchDescriptor<MealLog>())
        #expect(beforeFailure.count == 1)
        #expect(afterFailure.count == 1)
        #expect(!readOnly.mainContext.hasChanges)
        let habitCountBeforeFailure = try readOnly.mainContext.fetchCount(FetchDescriptor<Habit>())
        let memoryCountBeforeFailure = try readOnly.mainContext.fetchCount(FetchDescriptor<CoachMemoryEntry>())
        readOnlyModel.coachHabitSuggestions = ["Unsaveable habit"]
        #expect(!readOnlyModel.addCoachSuggestedHabit(name: "Unsaveable habit"))
        #expect(readOnlyModel.errorMessage != nil)
        #expect(readOnlyModel.followUpSuccessMessage.isEmpty)
        #expect(readOnlyModel.justAddedCoachHabit == nil)
        #expect(readOnlyModel.coachHabitSuggestions == ["Unsaveable habit"])
        #expect(try readOnly.mainContext.fetchCount(FetchDescriptor<Habit>()) == habitCountBeforeFailure)
        #expect(try readOnly.mainContext.fetchCount(FetchDescriptor<CoachMemoryEntry>()) == memoryCountBeforeFailure)
        #expect(!readOnly.mainContext.hasChanges)
        try model.deleteAllLocalRecords()
        for type in LuminaApp.modelTypes { #expect(try count(type, in: context) == 0) }
        #expect(try restored.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 1)
        #expect(model.dataRevision == 1)
        await model.bootstrapAfterLaunch()
        #expect(model.currentUser == nil && model.recentHealthSnapshots.isEmpty)
    }

    @MainActor
    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @MainActor
    @Test func offlineFollowUpSeparatesCheckInsFromHabitCompletions() async throws {
        for hasLegacyOutcomeClaim in [false, true] {
            let schema = Schema(LuminaApp.modelTypes)
            let container = try ModelContainer(for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let model = LuminaViewModel(modelContext: container.mainContext)
            let habit = Habit(name: "Fixture habit")
            container.mainContext.insert(habit)
            try container.mainContext.save()
            model.smartMemorySummary = "Added a new habit."
            if hasLegacyOutcomeClaim {
                model.persistedCoachMemory = [CoachMemoryEntry(type: .pattern,
                    content: "Earlier prototype note: coach habit has limited visible impact")]
            }
            model.followUpSuccessMessage = "Earlier success message"

            await model.generatePostActionFollowUp(after: .reviewPlan, actionTitle: "Added a new habit")

            let followUp = model.postActionCoachFollowUp.lowercased()
            #expect(model.showingPostActionFollowUp)
            #expect(model.postActionFollowUpAction == .logCheckIn)
            #expect(model.followUpSuccessMessage.isEmpty)
            #expect(followUp.contains("check-in"))
            #expect(followUp.contains("habit completions separately in habits"))
            #expect(!followUp.contains("first completion") && !followUp.contains("first win"))
            #expect(!followUp.contains("clear results") && !followUp.contains("photo"))
            #expect(habit.lastCompletedDate == nil && habit.totalCompletions == 0)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<DailyCheckIn>()) == 0)
        }
    }

    @MainActor
    @Test func releaseCoachingDoesNotRequireCloudCredentials() async throws {
        let context = CoachContext(profile: nil, recentHealth: [], recentCheckIns: [],
            recentWorkouts: [], recentMeals: [], activeHabits: [], recentInsights: [], currentStreak: 0)
        let service = GrokService(apiKey: "invalid-offline-release-test-key")
        let reflection = try await service.getWeeklyReflection(
            context: context, workoutsCompleted: 0, avgEnergy: 0)
        #expect(GrokService.configuredAPIKey == nil)
        #expect(reflection.contains("0 workouts"))
        let reply = try await service.getSmartEmotionalSupport(userMessage: "Am I making progress?", context: context)
        #expect(reply.contains("cannot determine physical progress"))
        #expect(!reply.contains("making real progress"))
        let direct = try await SmartGrokCoach(apiKey: "ignored-free-local-fixture").respondToUser(
            message: "Am I making progress?", context: context)
        #expect(direct == reply)
        let withoutGuessedMetrics = try await service.getWeeklyReflection(
            context: context, workoutsCompleted: 99, avgEnergy: 6.8)
        #expect(withoutGuessedMetrics == reflection)
        #expect(!withoutGuessedMetrics.contains("99 workouts"))
    }

}
