import SwiftUI

struct WeeklyInsightsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("This Week")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    Text("You trained 5/7 days. Your average energy was 6.8/10. Great consistency despite lower sleep on Tuesday and Wednesday.")
                }
                
                GlassCard {
                    Text("AI Insight")
                        .font(.headline)
                    Text("Your HRV dropped mid-week. The lighter sessions you chose were a smart move.")
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Insights")
    }
}
