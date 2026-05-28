import SwiftUI

struct RecoveryScoreCard: View {
    let snapshot: HealthSnapshot?
    
    var body: some View {
        GlassCard {
            if let snapshot = snapshot {
                let recovery = RecoveryScore.calculate(from: snapshot)
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Recovery Score")
                            .font(.headline)
                        Spacer()
                        Text("\(recovery.score)")
                            .font(.title.bold())
                            .foregroundStyle(recovery.color == "green" ? .green : recovery.color == "yellow" ? .yellow : .red)
                    }
                    
                    Text(recovery.label)
                        .font(.subheadline.bold())
                    
                    Text(recovery.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            } else {
                Text("No recent recovery data")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
