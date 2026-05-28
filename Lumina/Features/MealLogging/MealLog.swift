import Foundation
import SwiftData

@Model
final class MealLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var mealName: String
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var notes: String?
    var photoData: Data?   // Round 37: Support for meal photo logging with AI coach feedback

    @Relationship
    var owner: UserProfile?

    init(date: Date = Date(), mealName: String, calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, notes: String? = nil, photoData: Data? = nil) {
        self.date = date
        self.mealName = mealName
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
        self.photoData = photoData
    }
}
