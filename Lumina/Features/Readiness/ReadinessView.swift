import SwiftUI

struct ReadinessView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    var body: some View {
        VStack(spacing: 20) {
            Text("No validated readiness score is available.")
            RecoveryScoreCard(snapshot: viewModel.recentHealthSnapshots.first)
        }
        .padding()
        .navigationTitle("Readiness")
    }
}
