import SwiftUI

struct RecoveryView: View {
    let recentSnapshot: HealthSnapshot?
    var body: some View {
        VStack(spacing: 20) {
            RecoveryScoreCard(snapshot: recentSnapshot)
            Text("No validated recovery score is available. Review your recorded measurements and how you feel.")
        }
        .padding()
        .navigationTitle("Health records")
    }
}
