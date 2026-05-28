import SwiftUI

struct TodayView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Today")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text("Readiness: 82")
                            .font(.title2.bold())
                        Text("Good day to train. Focus on strength.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text("Workout")
                            .font(.headline)
                        Text("Push Day • 4 exercises • 50 min")
                        GlassButton(title: "Start Workout", isProminent: true) {}
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text("Nutrition Targets")
                            .font(.headline)
                        HStack {
                            Text("Protein: 180g")
                            Spacer()
                            Text("Calories: 2450")
                        }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text("Coach Note")
                            .font(.headline)
                        Text("You've been consistent for 12 days. Proud of you.")
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Today")
    }
}
