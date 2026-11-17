import Foundation
import SwiftData

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var isActive: Bool = true
    
    // Tracking
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var totalCompletions: Int = 0
    var lastCompletedDate: Date?
    
    // Coach intelligence
    var coachSuggested: Bool = false
    var coachNotes: String?
    var targetFrequencyPerWeek: Int = 7   // How many times per week the coach recommends

    // Capture the prior state in optional stored fields, leaving existing data
    // fields intact, so Undo can restore the counters and date after relaunch.
    private var undoCompletionDate: Date?
    private var undoPreviousCompletionDate: Date?
    private var undoPreviousStreak: Int?
    private var undoPreviousBestStreak: Int?
    private var undoPreviousTotalCompletions: Int?
    
    func toggleCompletion(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if let last = lastCompletedDate, calendar.isDate(last, inSameDayAs: today) {
            if let undoDate = undoCompletionDate, calendar.isDate(undoDate, inSameDayAs: today),
               let previousStreak = undoPreviousStreak,
               let previousBest = undoPreviousBestStreak,
               let previousTotal = undoPreviousTotalCompletions {
                lastCompletedDate = undoPreviousCompletionDate
                currentStreak = previousStreak
                bestStreak = previousBest
                totalCompletions = previousTotal
            } else {
                // Older saved completions have no reversible snapshot. Preserve
                // their existing behavior without guessing an earlier best.
                lastCompletedDate = currentStreak > 1 ? calendar.date(byAdding: .day, value: -1, to: today) : nil
                currentStreak = max(0, currentStreak - 1)
                totalCompletions = max(0, totalCompletions - 1)
            }
            undoCompletionDate = nil
            undoPreviousCompletionDate = nil
            undoPreviousStreak = nil
            undoPreviousBestStreak = nil
            undoPreviousTotalCompletions = nil
        } else {
            undoCompletionDate = today
            undoPreviousCompletionDate = lastCompletedDate
            undoPreviousStreak = currentStreak
            undoPreviousBestStreak = bestStreak
            undoPreviousTotalCompletions = totalCompletions
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
            let consecutive = lastCompletedDate.map { calendar.startOfDay(for: $0) == yesterday } ?? false
            currentStreak = consecutive ? currentStreak + 1 : 1
            lastCompletedDate = today
            totalCompletions += 1
            bestStreak = max(bestStreak, currentStreak)
        }
    }

    init(name: String, coachSuggested: Bool = false) {
        self.name = name
        self.coachSuggested = coachSuggested
    }
}

// Value-only access for a validated journal recovery. The five existing optional
// fields keep the same schema, names and values; no migration or reset is added.
struct HabitJournalRecoveryUndo {
    let undoCompletionDate: Date?
    let undoPreviousCompletionDate: Date?
    let undoPreviousStreak: Int?
    let undoPreviousBestStreak: Int?
    let undoPreviousTotalCompletions: Int?
}

extension Habit {
    var journalRecoveryUndo: HabitJournalRecoveryUndo {
        HabitJournalRecoveryUndo(undoCompletionDate: undoCompletionDate,
            undoPreviousCompletionDate: undoPreviousCompletionDate,
            undoPreviousStreak: undoPreviousStreak, undoPreviousBestStreak: undoPreviousBestStreak,
            undoPreviousTotalCompletions: undoPreviousTotalCompletions)
    }

    func applyJournalRecoveryUndo(_ record: JournalRecoveryRecord) throws {
        undoCompletionDate = try record.fields["undoCompletionDate"].map { _ in try record.date("undoCompletionDate") }
        undoPreviousCompletionDate = try record.fields["undoPreviousCompletionDate"].map { _ in try record.date("undoPreviousCompletionDate") }
        undoPreviousStreak = try record.fields["undoPreviousStreak"].map { _ in try record.integer("undoPreviousStreak") }
        undoPreviousBestStreak = try record.fields["undoPreviousBestStreak"].map { _ in try record.integer("undoPreviousBestStreak") }
        undoPreviousTotalCompletions = try record.fields["undoPreviousTotalCompletions"].map { _ in try record.integer("undoPreviousTotalCompletions") }
    }
}
