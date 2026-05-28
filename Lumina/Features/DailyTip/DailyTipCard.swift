import SwiftUI

struct DailyTipCard: View {
    let tip: String
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Daily Tip from your coach")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                Text(tip)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
