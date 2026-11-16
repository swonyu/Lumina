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
    
    func toggleCompletion(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if let last = lastCompletedDate, calendar.isDate(last, inSameDayAs: today) {
            lastCompletedDate = currentStreak > 1 ? calendar.date(byAdding: .day, value: -1, to: today) : nil
            currentStreak = max(0, currentStreak - 1)
            totalCompletions = max(0, totalCompletions - 1)
        } else {
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