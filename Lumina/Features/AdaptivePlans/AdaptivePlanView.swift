import SwiftUI

/// Now powered by the real Grok AI coach when an XAI_API_KEY is set.
/// Falls back to smart local analysis + the ability to request a full LLM plan.
struct AdaptivePlanView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    @State private var aiSuggestion: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    // Read from persisted value so the plan doesn't disappear on navigation
    private var displayedPlan: String? {
        aiSuggestion ?? viewModel.lastGeneratedAIPlan
    }
    
    private var grokService: GrokService? {
        if let key = GrokService.configuredAPIKey, !key.isEmpty {
            return GrokService(apiKey: key)
        }
        return nil
    }
    
    private var localSuggestion: String? {
        AdaptivePlanLogic.shouldAdjustPlan(
            recentCheckIns: [], // Could be enhanced to pull real recent data
            recentSnapshots: viewModel.recentHealthSnapshots
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
                                    Text("Coach note from your patterns")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.purple.opacity(0.9))
                                    Text("These are general suggestions; no health trend or safe training increase has been established.")
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
                        
                        if let local = localSuggestion {
                            Text(local)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.9))
                        } else {
                            Text("No automatic training adjustment has been made. Use your own records and how you feel to decide what is manageable.")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                
                #if DEBUG
                // Cloud coaching is excluded from the first offline release.
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("Grok Coach Recommendation")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            if grokService == nil {
                                Text("(set XAI_API_KEY)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        
                        if isGenerating {
                            HStack {
                                ProgressView()
                                Text("Grok is thinking...")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        } else if let plan = displayedPlan {
                            Text(plan)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.95))
                        } else {
                            Text("Tap the button below for a personalized, data-aware plan from Grok.")
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        
                        Button {
                            Task { await generateWithGrok() }
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text(grokService != nil ? "Get AI Plan from Grok" : "AI Plan (needs API key)")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(grokService != nil ? .purple.opacity(0.3) : .gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating || grokService == nil)
                    }
                }
                
                GlassButton(title: L("adaptive.apply_button"), isProminent: true, action: {
                    // TODO: Actually persist the chosen plan into the user's current program
                })
                
                Text("The AI recommendation factors in your recent energy, sleep, HRV, soreness, and goals.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 4)
                #endif
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("adaptive.nav_title"))
        .withAppLanguage()
        .drawingGroup() // Round 16 perf
    }
    
    private func generateWithGrok() async {
        guard let service = grokService else { return }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            let context = viewModel.buildCoachContext()
            if let profile = viewModel.currentUser {
                let result = try await service.generateSmartWorkoutPlan(profile: profile, context: context)
                aiSuggestion = result
                viewModel.lastGeneratedAIPlan = result   // persist so it survives navigation
            } else {
                errorMessage = "No profile yet. Create one in Settings."
            }
        } catch {
            errorMessage = "Grok request failed: \(error.localizedDescription.prefix(120))"
        }
        
        isGenerating = false
    }
}
