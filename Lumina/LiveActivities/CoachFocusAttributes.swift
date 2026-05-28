import ActivityKit
import Foundation

struct CoachFocusAttributes: ActivityAttributes {
    public struct RingValues: Codable, Hashable, Equatable {
        var readiness: Int
        var recovery: Int
        var nutrition: Int
    }

    public struct ContentState: Codable, Hashable, Equatable {
        var title: String
        var subtitle: String
        var progress: Double // 0.0 to 1.0 for the day
        var rings: RingValues
    }

    var coachName: String = "Lumina Coach"
}