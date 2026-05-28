import Foundation
import SwiftData

@Model
final class Streak {
    var id: UUID = UUID()
    var type: StreakType
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastCheckIn: Date?

    init(type: StreakType) {
        self.type = type
    }
}

enum StreakType: String, Codable {
    case workout
    case checkIn
    case nutrition
}
