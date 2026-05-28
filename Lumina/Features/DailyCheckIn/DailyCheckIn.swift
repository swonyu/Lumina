import Foundation
import SwiftData

@Model
final class DailyCheckIn {
    var id: UUID = UUID()
    var date: Date = Date()
    var energyLevel: Int          // 1-10
    var sorenessLevel: Int        // 1-10
    var sleepQuality: Int         // 1-10
    var stressLevel: Int          // 1-10
    var mood: Mood
    var journalNote: String?
    var didTrain: Bool = false

    init(
        date: Date = Date(),
        energyLevel: Int,
        sorenessLevel: Int,
        sleepQuality: Int,
        stressLevel: Int,
        mood: Mood,
        journalNote: String? = nil,
        didTrain: Bool = false
    ) {
        self.date = date
        self.energyLevel = energyLevel
        self.sorenessLevel = sorenessLevel
        self.sleepQuality = sleepQuality
        self.stressLevel = stressLevel
        self.mood = mood
        self.journalNote = journalNote
        self.didTrain = didTrain
    }
}
