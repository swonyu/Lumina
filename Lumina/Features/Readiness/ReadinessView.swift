import SwiftUI

struct ReadinessView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Today's Readiness")
                .font(.largeTitle.bold())
            
            GlassCard {
                VStack {
                    Text("82")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                    Text("Ready to Train Hard")
                        .font(.title3)
                }
            }
            
            GlassCard {
                Text("Based on your HRV, sleep, and recent check-ins, today is a great day to push.")
            }
        }
        .padding()
        .glassBackground()
        .navigationTitle("Readiness")
    }
}
