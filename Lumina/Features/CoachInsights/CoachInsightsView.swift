import SwiftUI

struct CoachInsightsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Coach Insights")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Week's Pattern")
                            .font(.headline)
                        Text("Your energy dips on Wednesdays. Consider moving heavy leg days to Tuesdays or Thursdays.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Observation")
                            .font(.headline)
                        Text("You've been more consistent when you check in before 9am. Small habit, big difference.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestion")
                            .font(.headline)
                        Text("Try adding 10-minute mobility on rest days. Your soreness scores have been trending down.")
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Insights")
    }
}
