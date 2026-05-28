import SwiftUI

struct RecoveryView: View {
    let recentSnapshot: HealthSnapshot?
    @Environment(LuminaViewModel.self) private var viewModel
    
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
                        Text(L("recovery.rest_message"))
                            .italic()
                    }
                }
            } else {
                Text(L("recovery.no_data"))
                    .foregroundStyle(.secondary)
            }
            
            // Round 31 + 61: Lightweight coach nudge from memory (now includes coach habit outcomes)
            if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                if mem.lowercased().contains("recovery") || mem.lowercased().contains("energy") || mem.lowercased().contains("sleep") || mem.lowercased().contains("coach habit") {
                    GlassCard {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.green)
                            let note: String = {
                                if viewModel.currentCoachPhotoReflectionShowsLimitedImpact || viewModel.hasLimitedCoachHabitImpact {
                                    return "Coach photo showed limited impact on a habit — review or adjust for better recovery?"
                                } else if mem.lowercased().contains("winning") || mem.lowercased().contains("delivering") {
                                    return "A coach habit is helping your recovery/energy — keep the streak going today."
                                } else if mem.lowercased().contains("low energy") {
                                    return "Low energy patterns detected recently — treat recovery as training today."
                                } else if mem.lowercased().contains("photo") && mem.lowercased().contains("coach") {
                                    return "Recent coach photo analysis may show recovery progress — check your Progress Photos."
                                } else if mem.lowercased().contains("coach habit") {
                                    return "A coach habit is showing impact on recovery — keep the momentum."
                                } else {
                                    return "Your patterns suggest recovery is a key lever right now. Prioritize it."
                                }
                            }()
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
        }
        .padding()
        .glassBackground()
        .navigationTitle(L("recovery.title"))
        .withAppLanguage()
        .drawingGroup() // Round 6 perf
    }
}
