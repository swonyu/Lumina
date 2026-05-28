import Foundation
import SwiftData

/// Persisted long-term memory for the AI coach so it actually gets smarter over time.
/// Stores both reflections and observed user patterns.
@Model
final class CoachMemoryEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var type: MemoryType
    var content: String
    
    init(type: MemoryType, content: String) {
        self.type = type
        self.content = content
    }
}

enum MemoryType: String, Codable, CaseIterable {
    case reflection = "reflection"
    case pattern = "pattern"
    case insight = "insight"
}