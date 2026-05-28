import SwiftUI

struct ReadinessView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text(L("readiness.title"))
                .font(.largeTitle.bold())
            
            GlassCard {
                VStack {
                    Text("82")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                    Text(L("readiness.ready_label"))
                        .font(.title3)
                }
            }
            
            GlassCard {
                Text(L("readiness.message"))
            }
            
            // Round 29: Proactive coach nudge powered by memory (when available)
            if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                GlassCard {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Coach insight")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue.opacity(0.9))
                                if !ProcessInfo.processInfo.environment["XAI_API_KEY", default: ""].isEmpty {
                                    Text("Grok")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.blue.opacity(0.6))
                                        .padding(.horizontal, 3)
                                        .background(.blue.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            let insight = viewModel.hasLimitedCoachHabitImpact
                                ? "Coach photo analysis showed limited impact on a habit — this may be affecting your readiness. Review it?"
                                : (mem.lowercased().contains("energy") || mem.lowercased().contains("tired") || mem.lowercased().contains("recovery")
                                    ? "Recent patterns suggest your readiness may be more variable than the number shows. Listen to body signals today."
                                    : "Your long-term data shows good self-awareness on recovery days. Use that strength.")
                            Text(insight)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
        }
        .padding()
        .glassBackground()
        .navigationTitle(L("readiness.nav_title"))
        .withAppLanguage()
        .drawingGroup() // Round 7 perf
    }
}
