import ActivityKit
import Foundation

struct CoachFocusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
    }
    var coachName: String = "Lumina Coach"
}
