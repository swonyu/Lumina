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
    
    init(name: String, coachSuggested: Bool = false) {
        self.name = name
        self.coachSuggested = coachSuggested
    }
}