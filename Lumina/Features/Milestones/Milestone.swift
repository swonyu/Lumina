import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var achievedDate: Date?
    var isAchieved: Bool = false
    var category: MilestoneCategory
    
    @Relationship
    var owner: UserProfile?
    
    init(title: String, description: String, category: MilestoneCategory) {
        self.title = title
        self.detail = description
        self.category = category
    }
}

enum MilestoneCategory: String, Codable {
    case consistency
    case strength
    case bodyComposition
    case mindset
}
