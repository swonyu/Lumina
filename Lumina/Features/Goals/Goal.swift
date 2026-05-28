import Foundation
import SwiftData

/// Persisted goal model so the AI coach can meaningfully adjust user goals over time.
@Model
final class Goal {
    var id: UUID = UUID()
    var name: String
    var currentValue: Double
    var targetValue: Double
    var unit: String
    var category: String          // e.g. "weight", "strength", "consistency"
    var lastAdjustedByCoach: Date?
    var adjustmentNotes: String?
    
    @Relationship(inverse: \UserProfile.goals)
    var owner: UserProfile?
    
    init(
        name: String,
        currentValue: Double = 0,
        targetValue: Double,
        unit: String = "",
        category: String = "general"
    ) {
        self.name = name
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.unit = unit
        self.category = category
    }
    
    var progress: Double {
        guard targetValue != 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }
}