import ActivityKit
import SwiftUI
import WidgetKit

struct CoachFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoachFocusAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.state.title).font(.headline)
                Text(context.state.subtitle).font(.caption)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text(context.state.title) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.subtitle) }
            } compactLeading: {
                Image(systemName: "book")
            } compactTrailing: {
                Text("Log")
            } minimal: {
                Image(systemName: "book")
            }
        }
    }
}
