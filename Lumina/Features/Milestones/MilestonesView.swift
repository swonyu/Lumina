import SwiftUI

struct MilestonesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Journey So Far")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🎉 30-Day Consistency Streak")
                            .font(.headline)
                        Text("You showed up even on the hard days. That’s rare and powerful.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💪 First Real Milestone")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("You haven’t hit one yet — but you’re building the foundation.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🧠 Mindset Shift")
                            .font(.headline)
                        Text("You started checking in with yourself instead of just pushing through.")
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Milestones")
    }
}
