import Foundation
import SwiftData

enum LocalRecordEditError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum LocalRecordDraft {
    static func name(_ value: String, field: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw LocalRecordEditError.invalid(L("Enter %@.", L(field))) }
        return result
    }

    static func numberText(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return "" }
        return String(value).replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
    }

    /// Whole-string parsing prevents a malformed draft from silently keeping an
    /// old numeric binding. Local decimal separators and decimal digits work;
    /// thousands separators are intentionally not accepted in an editing field.
    static func number(_ value: String, field: String, required: Bool = false,
                       locale: Locale = .current) throws -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard !required else { throw LocalRecordEditError.invalid(L("Enter %@.", L(field))) }
            return nil
        }
        let digits = trimmed.map { character -> String in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { return String(digit) }
            return String(character)
        }.joined()
        let normalized = digits.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard normalized.range(of: #"^[+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                               options: .regularExpression) != nil,
              let result = Double(normalized), result.isFinite, result >= 0 else {
            throw LocalRecordEditError.invalid(L("Enter a nonnegative number for %@, without thousands separators.", L(field)))
        }
        return result
    }

    static func wholeNumber(_ value: String, field: String, range: ClosedRange<Int>) throws -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let normalized = text.map { character -> String in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { return String(digit) }
            return String(character)
        }.joined()
        guard let result = Int(normalized), range.contains(result) else {
            throw LocalRecordEditError.invalid(L("Enter a valid whole number for %@.", L(field)))
        }
        return result
    }


}

extension LuminaViewModel {
    func requireCurrentEditSession() throws {
        guard dataRevision == 0 else {
            throw LocalRecordEditError.invalid(L("These records were cleared. Return to Home before editing a new entry."))
        }
    }

    /// Edit local draft values only after Save; a failed transaction rolls back.
    func commitLocalEdit(_ changes: () throws -> Void) throws {
        try requireCurrentEditSession()
        guard modelContext.container.configurations.allSatisfy(\.allowsSave) else {
            throw LocalRecordEditError.invalid(L("This store is read-only. Your draft has been kept."))
        }
        if modelContext.hasChanges { try modelContext.save() }
        do { try modelContext.transaction { try changes() } }
        catch { modelContext.rollback(); throw error }
        invalidateWorkoutsCache()
        invalidateHabitsCache()
    }

    func deleteLocalRecord<T: PersistentModel>(_ record: T) throws {
        try commitLocalEdit { modelContext.delete(record) }
    }

    func allActiveHabits() throws -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.isActive })
        return try modelContext.fetch(descriptor)
    }

    func validateHabitName(_ value: String, excluding id: UUID? = nil) throws -> String {
        let name = try LocalRecordDraft.name(value, field: "a habit name")
        let duplicate = try allActiveHabits().contains { habit in
            habit.id != id && habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(name, options: .caseInsensitive) == .orderedSame
        }
        guard !duplicate else { throw LocalRecordEditError.invalid(L("This habit is already in your list.")) }
        return name
    }

    @discardableResult
    func addLocalHabit(name: String) -> Bool {
        do {
            let name = try validateHabitName(name)
            guard saveRecord(Habit(name: name)) else { return false }
            invalidateHabitsCache()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}


/// String-backed drafts retain invalid input until it is corrected. A numeric
/// TextField binding can otherwise retain its old number after a parse failure.
struct WorkoutSetDraft: Identifiable {
    let id: UUID
    var repetitions: String
    var weight: String
    var exertion: String

    init(_ value: LoggedSet = LoggedSet(reps: 8, weight: nil)) {
        id = value.id
        repetitions = String(value.reps)
        weight = LocalRecordDraft.numberText(value.weight)
        exertion = value.rpe.map(String.init) ?? ""
    }

    func validated() throws -> LoggedSet {
        guard let reps = try LocalRecordDraft.wholeNumber(repetitions,
            field: "repetitions", range: 1...Int.max) else {
            throw LocalRecordEditError.invalid(L("Enter repetitions for each set."))
        }
        return LoggedSet(id: id, reps: reps,
            weight: try LocalRecordDraft.number(weight, field: "weight"),
            rpe: try LocalRecordDraft.wholeNumber(exertion, field: "set exertion", range: 1...10))
    }
}

struct WorkoutExerciseDraft: Identifiable {
    let id: UUID
    var name: String
    var sets: [WorkoutSetDraft]

    init(_ value: LoggedExercise = LoggedExercise(name: "", sets: [])) {
        id = value.id
        name = value.name
        sets = value.sets.map { WorkoutSetDraft($0) }
    }

    func validated() throws -> LoggedExercise {
        LoggedExercise(id: id, name: try LocalRecordDraft.name(name, field: "an exercise name"),
                       sets: try sets.map { try $0.validated() })
    }
}

@MainActor
struct JournalEditDraft {
    var title: String
    var content: String
    var mood: Mood?
    var date: Date

    init(_ entry: JournalEntry) {
        title = entry.title ?? ""
        content = entry.content
        mood = entry.mood
        date = entry.date
    }

    func save(to entry: JournalEntry, using viewModel: LuminaViewModel) throws {
        _ = try LocalRecordDraft.name(content, field: "journal text")
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try viewModel.commitLocalEdit {
            entry.title = cleanTitle.isEmpty ? nil : cleanTitle
            entry.content = content
            entry.mood = mood
            entry.date = date
        }
    }
}

@MainActor
struct GoalEditDraft {
    var name: String
    var current: String
    var target: String
    var unit: String
    var category: String

    init(_ goal: Goal? = nil) {
        name = goal?.name ?? ""
        current = LocalRecordDraft.numberText(goal?.currentValue ?? 0)
        target = LocalRecordDraft.numberText(goal?.targetValue ?? 1)
        unit = goal?.unit ?? "completion"
        category = goal?.category ?? "general"
    }

    func save(to goal: Goal?, using viewModel: LuminaViewModel) throws {
        let cleanName = try LocalRecordDraft.name(name, field: "a goal name")
        guard let currentValue = try LocalRecordDraft.number(current, field: "the current value", required: true),
              let targetValue = try LocalRecordDraft.number(target, field: "the target value", required: true) else {
            throw LocalRecordEditError.invalid(L("Enter current and target values."))
        }
        guard targetValue > 0 else { throw LocalRecordEditError.invalid(L("The target must be greater than zero.")) }
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        try viewModel.commitLocalEdit {
            if let goal {
                goal.name = cleanName
                goal.currentValue = currentValue
                goal.targetValue = targetValue
                goal.unit = cleanUnit
                goal.category = cleanCategory
            } else {
                viewModel.modelContext.insert(Goal(name: cleanName, currentValue: currentValue,
                    targetValue: targetValue, unit: cleanUnit, category: cleanCategory))
            }
        }
        viewModel.loadGoals()
    }
}

@MainActor
struct WorkoutEditDraft {
    var name: String
    var date: Date
    var notes: String
    var exercises: [WorkoutExerciseDraft]
    var exertion: String
    var duration: String

    init(_ log: WorkoutLog) {
        name = log.workoutName
        date = log.date
        notes = log.notes ?? ""
        exercises = log.exercises.map { WorkoutExerciseDraft($0) }
        exertion = log.perceivedExertion.map(String.init) ?? ""
        duration = log.durationMinutes.map(String.init) ?? ""
    }

    func save(to log: WorkoutLog, using viewModel: LuminaViewModel) throws {
        let cleanName = try LocalRecordDraft.name(name, field: "a workout name")
        let cleanedExercises = try exercises.map { try $0.validated() }
        let rpe = try LocalRecordDraft.wholeNumber(exertion, field: "exertion", range: 1...10)
        let minutes = try LocalRecordDraft.wholeNumber(duration, field: "duration", range: 1...Int.max)
        try viewModel.commitLocalEdit {
            log.workoutName = cleanName
            log.date = date
            log.notes = notes.isEmpty ? nil : notes
            log.exercises = cleanedExercises
            log.perceivedExertion = rpe
            log.durationMinutes = minutes
        }
    }
}

@MainActor
struct MealEditDraft {
    var name: String
    var date: Date
    var calories: String
    var protein: String
    var carbs: String
    var fat: String
    var notes: String
    var photoData: Data?

    init(_ meal: MealLog) {
        name = meal.mealName
        date = meal.date
        calories = LocalRecordDraft.numberText(meal.calories)
        protein = LocalRecordDraft.numberText(meal.protein)
        carbs = LocalRecordDraft.numberText(meal.carbs)
        fat = LocalRecordDraft.numberText(meal.fat)
        notes = meal.notes ?? ""
        photoData = meal.photoData
    }

    func save(to meal: MealLog, using viewModel: LuminaViewModel) throws {
        let cleanName = try LocalRecordDraft.name(name, field: "a meal name")
        let c = try LocalRecordDraft.number(calories, field: "calories")
        let p = try LocalRecordDraft.number(protein, field: "protein")
        let carbohydrate = try LocalRecordDraft.number(carbs, field: "carbohydrates")
        let f = try LocalRecordDraft.number(fat, field: "fat")
        try viewModel.commitLocalEdit {
            meal.mealName = cleanName
            meal.date = date
            meal.calories = c
            meal.protein = p
            meal.carbs = carbohydrate
            meal.fat = f
            meal.notes = notes.isEmpty ? nil : notes
            meal.photoData = photoData
        }
    }
}

@MainActor
struct CheckInEditDraft {
    var date: Date
    var energy: Int
    var soreness: Int
    var sleep: Int
    var stress: Int
    var mood: Mood
    var note: String
    var didTrain: Bool

    init(_ checkIn: DailyCheckIn) {
        date = checkIn.date
        energy = checkIn.energyLevel
        soreness = checkIn.sorenessLevel
        sleep = checkIn.sleepQuality
        stress = checkIn.stressLevel
        mood = checkIn.mood
        note = checkIn.journalNote ?? ""
        didTrain = checkIn.didTrain
    }

    func save(to checkIn: DailyCheckIn, using viewModel: LuminaViewModel) throws {
        guard [energy, soreness, sleep, stress].allSatisfy({ (1...10).contains($0) }) else {
            throw LocalRecordEditError.invalid(L("Each rating must be between 1 and 10."))
        }
        try viewModel.commitLocalEdit {
            checkIn.date = date
            checkIn.energyLevel = energy
            checkIn.sorenessLevel = soreness
            checkIn.sleepQuality = sleep
            checkIn.stressLevel = stress
            checkIn.mood = mood
            checkIn.journalNote = note.isEmpty ? nil : note
            checkIn.didTrain = didTrain
        }
    }
}

@MainActor
struct HabitEditDraft {
    var name: String
    var active: Bool
    var frequency: Int

    init(_ habit: Habit) {
        name = habit.name
        active = habit.isActive
        frequency = habit.targetFrequencyPerWeek
    }

    func save(to habit: Habit, using viewModel: LuminaViewModel) throws {
        try viewModel.requireCurrentEditSession()
        let cleanName: String
        if active {
            cleanName = try viewModel.validateHabitName(name, excluding: habit.id)
        } else {
            cleanName = try LocalRecordDraft.name(name, field: "a habit name")
        }
        guard (1...7).contains(frequency) else {
            throw LocalRecordEditError.invalid(L("The weekly target must be between 1 and 7 days."))
        }
        try viewModel.commitLocalEdit {
            habit.name = cleanName
            habit.isActive = active
            habit.targetFrequencyPerWeek = frequency
        }
    }
}
