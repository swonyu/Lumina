import Foundation
import SwiftData
import Testing
@testable import Lumina

@MainActor
struct HabitUndoIntegrityTests {
    @Test func undoAfterGapRestoresExactPriorStateAcrossReopen() throws {
        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = testCalendar()
        let now = testDate(calendar)
        let habit = Habit(name: "Evening walk", coachSuggested: true)
        habit.lastCompletedDate = calendar.date(byAdding: .day, value: -3, to: now)
        habit.currentStreak = 7
        habit.bestStreak = 12
        habit.totalCompletions = 30
        habit.coachNotes = "Original saved note"
        habit.targetFrequencyPerWeek = 4
        #expect(model.saveRecord(habit))
        let prior = HabitState(habit)
        try model.commitLocalEdit { habit.toggleCompletion(now: now, calendar: calendar) }
        #expect(habit.currentStreak == 1 && habit.totalCompletions == 31)

        let reopened = try reopen(directory)
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<Habit>()).first)
        let reopenedModel = LuminaViewModel(modelContext: reopened.mainContext)
        try reopenedModel.commitLocalEdit { restored.toggleCompletion(now: now, calendar: calendar) }
        #expect(prior.matches(restored))
        let persisted = try reopen(directory)
        let final = try #require(persisted.mainContext.fetch(FetchDescriptor<Habit>()).first)
        #expect(prior.matches(final))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Habit>()) == 1)
    }

    @Test func undoRestoresNewPersonalBestAndFirstCompletionExactly() {
        let calendar = testCalendar()
        let now = testDate(calendar)
        let first = Habit(name: "First completion")
        let empty = HabitState(first)
        first.toggleCompletion(now: now, calendar: calendar)
        #expect(first.currentStreak == 1 && first.bestStreak == 1 && first.totalCompletions == 1)
        first.toggleCompletion(now: now, calendar: calendar)
        #expect(empty.matches(first))

        let record = Habit(name: "Existing streak")
        record.lastCompletedDate = calendar.date(byAdding: .day, value: -1, to: now)
        record.currentStreak = 4
        record.bestStreak = 4
        record.totalCompletions = 12
        let prior = HabitState(record)
        for _ in 0..<2 {
            record.toggleCompletion(now: now, calendar: calendar)
            #expect(record.currentStreak == 5 && record.bestStreak == 5 && record.totalCompletions == 13)
            record.toggleCompletion(now: now, calendar: calendar)
            #expect(prior.matches(record))
        }
        record.toggleCompletion(now: now, calendar: calendar)
        record.name = "Renamed after completing"
        record.targetFrequencyPerWeek = 3
        record.toggleCompletion(now: now, calendar: calendar)
        #expect(record.name == "Renamed after completing" && record.targetFrequencyPerWeek == 3)
        #expect(record.currentStreak == 4 && record.bestStreak == 4 && record.totalCompletions == 12)
    }

    @Test func nextDayUndoRestoresOnlyTheMostRecentCompletion() throws {
        let calendar = testCalendar()
        let day = testDate(calendar)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let habit = Habit(name: "Two days")
        habit.toggleCompletion(now: day, calendar: calendar)
        let afterFirst = HabitState(habit)
        habit.toggleCompletion(now: next, calendar: calendar)
        #expect(habit.currentStreak == 2 && habit.bestStreak == 2 && habit.totalCompletions == 2)
        habit.toggleCompletion(now: next, calendar: calendar)
        #expect(afterFirst.matches(habit))
        habit.toggleCompletion(now: next, calendar: calendar)
        #expect(habit.currentStreak == 2 && habit.totalCompletions == 2)
    }

    @Test func failedCompletionTransactionCannotLeaveUndoStateOrCountersBehind() throws {
        let (directory, container, model) = try makeStore()
        // ModelContext does not own its container. Keep the fixture store alive
        // through the entire rollback/reopen contract, including optimized tests.
        defer { withExtendedLifetime(container) {} }
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = testCalendar()
        let now = testDate(calendar)
        let habit = Habit(name: "Rollback fixture")
        habit.lastCompletedDate = calendar.date(byAdding: .day, value: -3, to: now)
        habit.currentStreak = 3
        habit.bestStreak = 5
        habit.totalCompletions = 10
        #expect(model.saveRecord(habit))
        let prior = HabitState(habit)
        #expect(throws: CocoaError.self) {
            try model.commitLocalEdit {
                habit.toggleCompletion(now: now, calendar: calendar)
                throw CocoaError(.fileWriteUnknown)
            }
        }
        #expect(prior.matches(habit) && !model.modelContext.hasChanges)
        let reopened = try reopen(directory)
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<Habit>()).first)
        #expect(prior.matches(saved))
        let currentModel = LuminaViewModel(modelContext: reopened.mainContext)
        try currentModel.commitLocalEdit { saved.toggleCompletion(now: now, calendar: calendar) }
        try currentModel.commitLocalEdit { saved.toggleCompletion(now: now, calendar: calendar) }
        #expect(prior.matches(saved))
    }

    @Test func previousHabitSchemaMigratesWithoutChangingSavedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lumina-habit-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = testCalendar()
        let now = testDate(calendar)
        let savedID = UUID()
        let inactiveID = UUID()
        let mealID = UUID()
        let journalID = UUID()
        let ownerID = UUID()
        let savedDate = try #require(calendar.date(byAdding: .day, value: -4, to: now))
        let photoBytes = Data([0, 1, 2, 127, 254, 255])
        var previousTypes = LuminaApp.modelTypes.filter { ObjectIdentifier($0) != ObjectIdentifier(Habit.self) }
        previousTypes.append(HabitBeforeUndo.Habit.self)
        let previousSchema = Schema(previousTypes)
        #expect(previousSchema.entities.filter { $0.name == "Habit" }.count == 1)
        let previousHabit = try #require(previousSchema.entitiesByName["Habit"])
        let oldFields: Set<String> = ["id", "name", "createdAt", "isActive", "currentStreak",
            "bestStreak", "totalCompletions", "lastCompletedDate", "coachSuggested",
            "coachNotes", "targetFrequencyPerWeek"]
        #expect(Set(previousHabit.attributesByName.keys) == oldFields)
        let currentSchema = Schema(LuminaApp.modelTypes)
        #expect(Set(previousSchema.entities.map(\.name)) == Set(currentSchema.entities.map(\.name)))
        let currentHabit = try #require(currentSchema.entitiesByName["Habit"])
        let undoFields: Set<String> = ["undoCompletionDate", "undoPreviousCompletionDate",
            "undoPreviousStreak", "undoPreviousBestStreak", "undoPreviousTotalCompletions"]
        #expect(Set(currentHabit.attributesByName.keys) == oldFields.union(undoFields))

        let legacyURL = directory.appendingPathComponent("legacy.sqlite")
        let oldStore: Data = try autoreleasepool {
            let previous = try ModelContainer(for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: legacyURL, cloudKitDatabase: .none)])
            let habit = HabitBeforeUndo.Habit(name: "Migrated habit", coachSuggested: true)
            habit.id = savedID
            habit.createdAt = savedDate
            habit.lastCompletedDate = savedDate
            habit.currentStreak = 7
            habit.bestStreak = 12
            habit.totalCompletions = 30
            habit.coachNotes = "Preserve historical note"
            habit.targetFrequencyPerWeek = 4
            previous.mainContext.insert(habit)

            let inactive = HabitBeforeUndo.Habit(name: "Archived migration habit")
            inactive.id = inactiveID
            inactive.createdAt = savedDate
            inactive.isActive = false
            inactive.bestStreak = 2
            inactive.totalCompletions = 4
            inactive.targetFrequencyPerWeek = 2
            previous.mainContext.insert(inactive)

            let owner = UserProfile(name: "Migration fixture owner", age: 32, gender: .other,
                heightCm: 170, currentWeightKg: 70, experienceLevel: .beginner,
                primaryGoal: .generalHealth, workoutDaysPerWeek: 3, equipmentAccess: .none)
            owner.id = ownerID
            owner.createdAt = savedDate
            owner.updatedAt = savedDate
            previous.mainContext.insert(owner)
            let meal = MealLog(date: savedDate, mealName: "Unrelated migration meal",
                calories: 421, protein: 25.5, carbs: 40.5, fat: 13.2,
                notes: "Preserve meal and image bytes", photoData: photoBytes)
            meal.id = mealID
            meal.owner = owner
            previous.mainContext.insert(meal)
            let journal = JournalEntry(date: savedDate, title: "Unrelated migration journal",
                content: "Saved line one\nملاحظة محفوظة", mood: .good, tags: ["migration", "fixture"])
            journal.id = journalID
            journal.owner = owner
            previous.mainContext.insert(journal)
            try previous.mainContext.save()
            #expect(try previous.mainContext.fetchCount(FetchDescriptor<HabitBeforeUndo.Habit>()) == 2)
            try verifyMigrationSentinels(previous.mainContext, date: savedDate, mealID: mealID,
                journalID: journalID, ownerID: ownerID, photoBytes: photoBytes)
            // The production SQLite backup API produces a complete, standalone
            // disk snapshot; migrating its copy cannot change the retained source.
            return try LuminaViewModel(modelContext: previous.mainContext).exportDatabase()
        }
        #expect(!oldStore.isEmpty)
        Attachment.record(oldStore, named: "Habit-legacy-11-fields-before-migration.sqlite")
        let fixtureURL = directory.appendingPathComponent("fixture.sqlite")
        try oldStore.write(to: fixtureURL, options: .atomic)

        // Reopen the actual persisted old-schema copy before migration. Merely
        // constructing old model objects in memory would not prove compatibility.
        try autoreleasepool {
            let previous = try ModelContainer(for: previousSchema,
                configurations: [ModelConfiguration(schema: previousSchema, url: fixtureURL, cloudKitDatabase: .none)])
            let habits = try previous.mainContext.fetch(FetchDescriptor<HabitBeforeUndo.Habit>())
            #expect(habits.count == 2)
            let saved = try #require(habits.first { $0.id == savedID })
            #expect(saved.name == "Migrated habit" && saved.createdAt == savedDate)
            #expect(saved.lastCompletedDate == savedDate && saved.currentStreak == 7)
            #expect(saved.bestStreak == 12 && saved.totalCompletions == 30)
            #expect(saved.isActive && saved.coachSuggested && saved.coachNotes == "Preserve historical note")
            #expect(saved.targetFrequencyPerWeek == 4)
            try verifyMigrationSentinels(previous.mainContext, date: savedDate, mealID: mealID,
                journalID: journalID, ownerID: ownerID, photoBytes: photoBytes)
        }

        let prior: HabitState = try autoreleasepool {
            let current = try reopen(directory)
            let habits = try current.mainContext.fetch(FetchDescriptor<Habit>())
            #expect(habits.count == 2)
            let habit = try #require(habits.first { $0.id == savedID })
            #expect(habit.id == savedID && habit.name == "Migrated habit" && habit.createdAt == savedDate)
            #expect(habit.currentStreak == 7 && habit.bestStreak == 12 && habit.totalCompletions == 30)
            #expect(habit.lastCompletedDate == savedDate && habit.coachSuggested && habit.isActive)
            #expect(habit.coachNotes == "Preserve historical note" && habit.targetFrequencyPerWeek == 4)
            try verifyInactiveMigrationHabit(habits, id: inactiveID, date: savedDate)
            try verifyMigrationSentinels(current.mainContext, date: savedDate, mealID: mealID,
                journalID: journalID, ownerID: ownerID, photoBytes: photoBytes)
            let prior = HabitState(habit)
            let model = LuminaViewModel(modelContext: current.mainContext)
            try model.commitLocalEdit { habit.toggleCompletion(now: now, calendar: calendar) }
            #expect(habit.currentStreak == 1 && habit.bestStreak == 12 && habit.totalCompletions == 31)
            #expect(habit.lastCompletedDate == calendar.startOfDay(for: now))
            Attachment.record(try model.exportDatabase(), named: "Habit-migrated-after-completion.sqlite")
            return prior
        }
        try autoreleasepool {
            let reopened = try reopen(directory)
            let habits = try reopened.mainContext.fetch(FetchDescriptor<Habit>())
            #expect(habits.count == 2)
            let habit = try #require(habits.first { $0.id == savedID })
            #expect(habit.currentStreak == 1 && habit.bestStreak == 12 && habit.totalCompletions == 31)
            #expect(habit.lastCompletedDate == calendar.startOfDay(for: now))
            let model = LuminaViewModel(modelContext: reopened.mainContext)
            try model.commitLocalEdit { habit.toggleCompletion(now: now, calendar: calendar) }
            #expect(prior.matches(habit))
        }
        try autoreleasepool {
            let final = try reopen(directory)
            let habits = try final.mainContext.fetch(FetchDescriptor<Habit>())
            #expect(habits.count == 2)
            let habit = try #require(habits.first { $0.id == savedID })
            #expect(prior.matches(habit))
            try verifyInactiveMigrationHabit(habits, id: inactiveID, date: savedDate)
            try verifyMigrationSentinels(final.mainContext, date: savedDate, mealID: mealID,
                journalID: journalID, ownerID: ownerID, photoBytes: photoBytes)
            Attachment.record(try LuminaViewModel(modelContext: final.mainContext).exportDatabase(),
                named: "Habit-migrated-after-undo-and-reopen.sqlite")
        }
        Attachment.record("Old Habit attributes: \(oldFields.sorted())\nNew Habit attributes: \(oldFields.union(undoFields).sorted())\nSchema entities: \(previousSchema.entities.map(\.name).sorted())\nActive habit: \(savedID)\nInactive habit: \(inactiveID)\nUnrelated meal: \(mealID)\nUnrelated journal: \(journalID)\nOwner: \(ownerID)",
            named: "Habit-migration-fixture-identities.txt")
    }

    private func verifyInactiveMigrationHabit(_ habits: [Habit], id: UUID, date: Date) throws {
        let inactive = try #require(habits.first { $0.id == id })
        #expect(inactive.name == "Archived migration habit" && inactive.createdAt == date)
        #expect(!inactive.isActive && !inactive.coachSuggested && inactive.coachNotes == nil)
        #expect(inactive.currentStreak == 0 && inactive.bestStreak == 2 && inactive.totalCompletions == 4)
        #expect(inactive.lastCompletedDate == nil && inactive.targetFrequencyPerWeek == 2)
    }

    private func verifyMigrationSentinels(_ context: ModelContext, date: Date, mealID: UUID,
                                          journalID: UUID, ownerID: UUID, photoBytes: Data) throws {
        let meals = try context.fetch(FetchDescriptor<MealLog>())
        #expect(meals.count == 1)
        let meal = try #require(meals.first)
        #expect(meal.id == mealID && meal.date == date && meal.mealName == "Unrelated migration meal")
        #expect(meal.calories == 421 && meal.protein == 25.5 && meal.carbs == 40.5 && meal.fat == 13.2)
        #expect(meal.notes == "Preserve meal and image bytes" && meal.photoData == photoBytes)
        #expect(meal.owner?.id == ownerID)
        let journals = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(journals.count == 1)
        let journal = try #require(journals.first)
        #expect(journal.id == journalID && journal.date == date && journal.title == "Unrelated migration journal")
        #expect(journal.content == "Saved line one\nملاحظة محفوظة" && journal.mood == .good)
        #expect(journal.tags == ["migration", "fixture"] && journal.owner?.id == ownerID)
        let owners = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(owners.count == 1)
        let owner = try #require(owners.first)
        #expect(owner.id == ownerID && owner.name == "Migration fixture owner")
        #expect(owner.age == 32 && owner.gender == .other && owner.heightCm == 170 && owner.currentWeightKg == 70)
        #expect(owner.goalWeightKg == nil && owner.experienceLevel == .beginner && owner.primaryGoal == .generalHealth)
        #expect(owner.workoutDaysPerWeek == 3 && owner.equipmentAccess == .none && owner.dietaryPreferences.isEmpty)
        #expect(owner.injuriesOrLimitations == nil && owner.createdAt == date && owner.updatedAt == date && owner.goals.isEmpty)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func testDate(_ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
    }

    private func makeStore() throws -> (URL, ModelContainer, LuminaViewModel) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lumina-habit-undo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try reopen(directory)
        return (directory, container, LuminaViewModel(modelContext: container.mainContext))
    }

    private func reopen(_ directory: URL) throws -> ModelContainer {
        let schema = Schema(LuminaApp.modelTypes)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("fixture.sqlite"), cloudKitDatabase: .none)])
    }
}

@MainActor
private struct HabitState {
    let id: UUID
    let name: String
    let createdAt: Date
    let isActive: Bool
    let currentStreak: Int
    let bestStreak: Int
    let totalCompletions: Int
    let lastCompletedDate: Date?
    let coachSuggested: Bool
    let coachNotes: String?
    let targetFrequencyPerWeek: Int

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
        createdAt = habit.createdAt
        isActive = habit.isActive
        currentStreak = habit.currentStreak
        bestStreak = habit.bestStreak
        totalCompletions = habit.totalCompletions
        lastCompletedDate = habit.lastCompletedDate
        coachSuggested = habit.coachSuggested
        coachNotes = habit.coachNotes
        targetFrequencyPerWeek = habit.targetFrequencyPerWeek
    }

    func matches(_ habit: Habit) -> Bool {
        id == habit.id && name == habit.name && createdAt == habit.createdAt
            && isActive == habit.isActive && currentStreak == habit.currentStreak
            && bestStreak == habit.bestStreak && totalCompletions == habit.totalCompletions
            && lastCompletedDate == habit.lastCompletedDate && coachSuggested == habit.coachSuggested
            && coachNotes == habit.coachNotes && targetFrequencyPerWeek == habit.targetFrequencyPerWeek
    }
}

// The exact persisted field layout of the pre-undo Habit model, scoped to this
// fixture so the full old schema can create an isolated pre-update SQLite store.
private enum HabitBeforeUndo {
    @Model
    final class Habit {
        var id: UUID = UUID()
        var name: String
        var createdAt: Date = Date()
        var isActive: Bool = true
        var currentStreak: Int = 0
        var bestStreak: Int = 0
        var totalCompletions: Int = 0
        var lastCompletedDate: Date?
        var coachSuggested: Bool = false
        var coachNotes: String?
        var targetFrequencyPerWeek: Int = 7

        init(name: String, coachSuggested: Bool = false) {
            self.name = name
            self.coachSuggested = coachSuggested
        }
    }
}
