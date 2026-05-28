import SwiftUI

struct MilestonesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("milestones.journey_title"))
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("milestones.streak_title"))
                            .font(.headline)
                        Text(L("milestones.streak_message"))
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("milestones.first_title"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(L("milestones.first_message"))
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("milestones.mindset_title"))
                            .font(.headline)
                        Text(L("milestones.mindset_message"))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.milestones"))
        .withAppLanguage()
        .drawingGroup() // Round 10 perf
    }
}
