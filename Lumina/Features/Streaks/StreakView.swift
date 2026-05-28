import SwiftUI

struct StreakView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Consistency")
                .font(.largeTitle.bold())
            
            GlassCard {
                HStack {
                    VStack {
                        Text("12")
                            .font(.system(size: 48, weight: .bold))
                        Text("Day Streak")
                    }
                    Spacer()
                    Text("🔥")
                        .font(.system(size: 60))
                }
            }
            
            GlassCard {
                Text("Longest streak: 28 days")
            }
        }
        .padding()
        .glassBackground()
    }
}
