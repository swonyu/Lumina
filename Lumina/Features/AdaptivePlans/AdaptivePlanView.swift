import SwiftUI

struct AdaptivePlanView: View {
    let suggestion: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Plan Adjustment")
                .font(.largeTitle.bold())
            
            if let suggestion = suggestion {
                GlassCard {
                    Text(suggestion)
                        .font(.body)
                }
                
                GlassButton(title: "Apply Adjustment", isProminent: true) {
                    // TODO: Update current plan
                }
            } else {
                Text("Your plan looks good based on recent data.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassBackground()
        .navigationTitle("Adaptive Plan")
    }
}
