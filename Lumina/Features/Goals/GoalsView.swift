import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    @State private var showingAddGoal = false
    @State private var editingGoal: Goal?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("goals.title"))
                    .font(.largeTitle.bold())
                
                if viewModel.goals.isEmpty {
                    GlassCard {
                        Text(L("No goals yet. Add a goal to record what you want to work toward."))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    ForEach(viewModel.goals) { goal in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(goal.name)
                                    .font(.headline)
                                Button(L("Edit goal")) { editingGoal = goal }
                                    .accessibilityLabel(L("Edit goal %@", goal.name))
                                ProgressView(value: goal.progress)
                                    .accessibilityLabel(L("Recorded goal ratio for %@", goal.name))
                                Text("\(LocalRecordDraft.numberText(goal.currentValue)) \(goal.unit) / \(LocalRecordDraft.numberText(goal.targetValue)) \(goal.unit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("lumina.goal.values")
                                
                                if let notes = goal.adjustmentNotes {
                                    Text(L("Saved adjustment note: %@", notes))
                                        .font(.caption2)
                                        .foregroundStyle(.yellow.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                
                // Round 12/13: Show AI coach goal adjustments when they exist
                if !viewModel.recentGoalAdjustments.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Saved adjustment notes"))
                                .font(.headline)
                            ForEach(viewModel.recentGoalAdjustments.prefix(3), id: \.self) { adj in
                                Text("• \(adj)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                }

                // Round 73 + 75 + 101: Smarter nudge for recent coach photo outcomes that may impact goals (now uses centralized computed)
                if viewModel.currentCoachPhotoReflectionShowsLimitedImpact || (viewModel.coachPhotoReflection != nil && !viewModel.coachPhotoReflection!.isEmpty) {
                    GlassCard {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            Text(L(viewModel.currentCoachPhotoReflectionShowsLimitedImpact
                                ? "Saved photo notes may mention habit effects. Those claims are unverified."
                                : "Saved photo notes are available. Review the original records alongside your goals."))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                
                // Round 29: Lightweight proactive nudge from the coach's memory directly in Goals
                if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                    let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                    if mem.lowercased().contains("goal") || mem.lowercased().contains("adjust") || mem.lowercased().contains("consistency") {
                        GlassCard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Text(L("Saved coaching notes"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.yellow.opacity(0.9))
                                        if !(GrokService.configuredAPIKey ?? "").isEmpty {
                                            Text(L("Grok"))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.yellow.opacity(0.6))
                                                .padding(.horizontal, 3)
                                                .background(.yellow.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(L("Review saved notes alongside your goals; notes do not establish progress."))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                
                GlassButton(title: L("goals.add_button"), action: {
                    showingAddGoal = true
                })
                .accessibilityIdentifier("lumina.goal.add")
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.goals"))
        .withAppLanguage()
        .sheet(isPresented: $showingAddGoal) {
            NavigationStack { GoalRecordEditor() }
        }
        .sheet(item: $editingGoal) { goal in
            NavigationStack { GoalRecordEditor(goal: goal) }
        }
        .onAppear { viewModel.loadGoals() }
    }
}

struct GoalItem: Identifiable {
    let id = UUID()
    var name: String
    var current: Double
    var target: Double
    var unit: String
    
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }
}
