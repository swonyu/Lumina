import SwiftUI

struct DailyInsightCard: View {
    let insight: String
    let date: Date = Date()
    
    var body: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Text("AI Daily Insight")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                Text(insight)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                
                GlassButton(title: "Ask for more details") {}
            }
        }
    }
}
