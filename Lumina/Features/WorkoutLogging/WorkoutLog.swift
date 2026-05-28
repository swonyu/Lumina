import Foundation
import SwiftData

@Model
final class WorkoutLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var workoutName: String
    var exercises: [LoggedExercise]
    var perceivedExertion: Int? // RPE 1-10
    var notes: String?
    var durationMinutes: Int?

    @Relationship
    var owner: UserProfile?

    init(date: Date = Date(), workoutName: String, exercises: [LoggedExercise] = [], perceivedExertion: Int? = nil, notes: String? = nil, durationMinutes: Int? = nil) {
        self.date = date
        self.workoutName = workoutName
        self.exercises = exercises
        self.perceivedExertion = perceivedExertion
        self.notes = notes
        self.durationMinutes = durationMinutes
    }
}

struct LoggedExercise: Codable, Identifiable {
    var id = UUID()
    var name: String
    var sets: [LoggedSet]
}

struct LoggedSet: Codable, Identifiable {
    var id = UUID()
    var reps: Int
    var weight: Double?
    var rpe: Int?
}
