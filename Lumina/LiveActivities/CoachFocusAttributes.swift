import ActivityKit
import Foundation

nonisolated struct CoachFocusAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
        var title: String
        var subtitle: String
    }
    var coachName: String = "Lumina Coach"
}
