import Foundation
import SwiftData

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String?
    var content: String
    var mood: Mood?
    var tags: [String] = []

    @Relationship
    var owner: UserProfile?

    init(date: Date = Date(), title: String? = nil, content: String, mood: Mood? = nil, tags: [String] = []) {
        self.date = date
        self.title = title
        self.content = content
        self.mood = mood
        self.tags = tags
    }
}
