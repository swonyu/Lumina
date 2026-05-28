import ActivityKit
import SwiftUI
import WidgetKit

struct CoachFocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoachFocusAttributes.self) { context in
            // Lock Screen / Banner UI
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text(context.attributes.coachName)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption.bold())
                }
                
                Text(context.state.title)
                    .font(.subheadline.weight(.semibold))
                
                Text(context.state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Mini rings
                HStack(spacing: 8) {
                    MiniRing(value: Double(context.state.rings.readiness) / 100, color: .green, label: "R")
                    MiniRing(value: Double(context.state.rings.recovery) / 100, color: .blue, label: "Rec")
                    MiniRing(value: Double(context.state.rings.nutrition) / 100, color: .orange, label: "Nut")
                }
            }
            .padding(12)
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack {
                        MiniRing(value: Double(context.state.rings.readiness) / 100, color: .green, label: "R")
                        Text("\(context.state.rings.readiness)")
                            .font(.caption2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack {
                        MiniRing(value: Double(context.state.rings.recovery) / 100, color: .blue, label: "Rec")
                        Text("\(context.state.rings.recovery)")
                            .font(.caption2)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle)
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.bold())
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct MiniRing: View {
    let value: Double
    let color: Color
    let label: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: value)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}