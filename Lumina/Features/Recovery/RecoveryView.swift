import SwiftUI

struct RecoveryView: View {
    let recentSnapshot: HealthSnapshot?
    
    var body: some View {
        VStack(spacing: 24) {
            if let snapshot = recentSnapshot {
                let recovery = RecoveryScore.calculate(from: snapshot)
                
                VStack {
                    Text("\(recovery.score)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                    Text(recovery.label)
                        .font(.title2.bold())
                }
                
                GlassCard {
                    Text(recovery.recommendation)
                        .multilineTextAlignment(.center)
                        .font(.body)
                }
                
                if recovery.score < 55 {
                    GlassCard {
                        Text("Your body is asking for rest. It's okay to take it easy today.")
                            .italic()
                    }
                }
            } else {
                Text("No recent recovery data")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassBackground()
        .navigationTitle("Recovery Today")
    }
}
