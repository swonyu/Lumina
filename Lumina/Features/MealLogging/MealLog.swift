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

    init(date: Date = Date(), mealName: String, calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil, notes: String? = nil) {
        self.date = date
        self.mealName = mealName
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
    }
}
