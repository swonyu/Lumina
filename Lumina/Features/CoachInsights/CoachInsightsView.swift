import SwiftUI

/// Reflection prompts; these do not claim a measured pattern or generated analysis.
struct CoachInsightsView: View {
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("coach.insights_title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                

                // Local reflection prompts do not invent measured health trends.
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("coach.insights_pattern_title"))
                            .font(.headline)
                        Text(L("coach.insights_pattern_message"))
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("coach.insights_observation_title"))
                            .font(.headline)
                        Text(L("coach.insights_observation_message"))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("coach.insights_nav_title"))
        .withAppLanguage()
    }
}
