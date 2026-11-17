import SwiftUI
import SwiftData

/// Describes a bounded set of saved records without inferring health readiness.
struct AdaptivePlanView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(AdaptivePlanLogic.checkInDescriptor) private var recentCheckIns: [DailyCheckIn]
    @Query(AdaptivePlanLogic.snapshotDescriptor) private var recentSnapshots: [HealthSnapshot]
    
    private var localSuggestion: String? {
        AdaptivePlanLogic.shouldAdjustPlan(
            recentCheckIns: recentCheckIns,
            recentSnapshots: recentSnapshots
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("adaptive.plan_adjustment_title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                // Round 32: Memory-driven coach nudge (when patterns are relevant)
                if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                    let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                    if mem.lowercased().contains("consistent") || mem.lowercased().contains("energy") || mem.lowercased().contains("recovery") || mem.lowercased().contains("goal") {
                        GlassCard {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Review your saved notes"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.purple.opacity(0.9))
                                    Text(L("These are general suggestions; no health trend or safe training increase has been established."))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                    }
                }
                
                // Local quick analysis (always available)
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.yellow)
                            Text(L("adaptive.quick_analysis"))
                                .font(.headline)
                        }
                        
                        if _recentCheckIns.fetchError != nil || _recentSnapshots.fetchError != nil {
                            Text(L("Saved records could not be loaded. Return to Home and open this screen again. No training adjustment has been made."))
                                .accessibilityIdentifier("lumina.training.records-error")
                        } else {
                            Text(L("Saved check-ins: %d. Health snapshots: %d. Reviews up to 14 of each, newest first. Review their dates; older prototype entries may not describe you.", recentCheckIns.count, recentSnapshots.count))
                                .font(.caption)
                                .accessibilityIdentifier("lumina.training.record-scope")
                            if recentCheckIns.isEmpty && recentSnapshots.isEmpty {
                                Text(L("No check-ins or health snapshots are saved. Add a Daily check-in from Home to record how you feel. No training adjustment has been made."))
                                    .accessibilityIdentifier("lumina.training.empty")
                            } else if let local = localSuggestion {
                                Text(local)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .accessibilityIdentifier("lumina.training.observation")
                            } else {
                                Text(L("No automatic training adjustment has been made. Use your own records and how you feel to decide what is manageable."))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("adaptive.local_outline_title"))
                            .font(.headline)
                        Text(LocalCoachRules.workoutOutline(locale: LocalizationManager.shared.currentLanguage.locale))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("lumina.training.local-outline")
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("adaptive.nav_title"))
        .withAppLanguage()
    }
}
