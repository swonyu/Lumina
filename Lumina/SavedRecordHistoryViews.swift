import SwiftUI
import SwiftData

struct WorkoutHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutLog.date, order: .reverse) private var records: [WorkoutLog]
    var body: some View {
        List {
            if records.isEmpty { Text(L("No saved workouts.")) }
            ForEach(records) { record in
                NavigationLink { WorkoutRecordEditor(log: record) } label: {
                    VStack(alignment: .leading) {
                        Text(record.workoutName)
                        Text(record.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(LocalizationManager.shared.currentLanguage.locale))).font(.caption)
                        Text(L("%d exercises recorded", record.exercises.count)).font(.caption)
                    }
                }
            }
        }
        .navigationTitle(L("Saved workouts")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() } } }
    }
}

struct MealHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MealLog.date, order: .reverse) private var records: [MealLog]
    var body: some View {
        List {
            if records.isEmpty { Text(L("No saved meals.")) }
            ForEach(records) { record in
                NavigationLink { MealRecordEditor(meal: record) } label: {
                    VStack(alignment: .leading) {
                        Text(record.mealName)
                        Text(record.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(LocalizationManager.shared.currentLanguage.locale))).font(.caption)
                        if record.photoData != nil { Label(L("Saved photo"), systemImage: "photo").font(.caption) }
                    }
                }
            }
        }
        .navigationTitle(L("Saved meals")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() } } }
    }
}

struct CheckInHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var records: [DailyCheckIn]
    var body: some View {
        List {
            if records.isEmpty { Text(L("No saved check-ins.")) }
            ForEach(records) { record in
                NavigationLink { CheckInRecordEditor(checkIn: record) } label: {
                    VStack(alignment: .leading) {
                        Text(record.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(LocalizationManager.shared.currentLanguage.locale)))
                        Text(L("Energy %d/10 · %@", record.energyLevel, L(record.mood.rawValue))).font(.caption)
                        if let note = record.journalNote { Text(note).lineLimit(2).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle(L("Saved check-ins")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() } } }
    }
}

struct HabitHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.createdAt, order: .reverse) private var records: [Habit]
    var body: some View {
        List {
            if records.isEmpty { Text(L("No saved habits.")) }
            ForEach(records) { record in
                NavigationLink { HabitRecordEditor(habit: record) } label: {
                    VStack(alignment: .leading) {
                        Text(record.name)
                            .accessibilityIdentifier("lumina.habit.history-name")
                        Text(L(record.isActive ? "Active" : "Inactive")).font(.caption)
                        Text(L("%d recorded completions", record.totalCompletions)).font(.caption)
                    }
                }
            }
        }
        .navigationTitle(L("Manage habits")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() } } }
    }
}
