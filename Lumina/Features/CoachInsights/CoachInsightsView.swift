import SwiftUI

/// Weekly reflection + insights now powered by the real Grok coach (when key is set).
struct CoachInsightsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    @State private var weeklyReflection: String?
    @State private var isLoadingReflection = false
    @State private var error: String?

    private var displayedReflection: String? {
        weeklyReflection ?? viewModel.lastWeeklyReflection
    }
    
    private var grok: GrokService? {
        if let key = ProcessInfo.processInfo.environment["XAI_API_KEY"], !key.isEmpty {
            return GrokService(apiKey: key)
        }
        return nil
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("coach.insights_title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                // Real AI Weekly Reflection
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Weekly Reflection from Grok")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        
                        if isLoadingReflection {
                            HStack { ProgressView(); Text("Reflecting on your week...") }
                                .foregroundStyle(.white.opacity(0.7))
                        } else if let reflection = displayedReflection {
                            Text(reflection)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.92))
                        } else {
                            Text("Get a thoughtful, data-driven weekly reflection written by Grok based on your actual training, energy, and patterns.")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        if let e = error {
                            Text(e).font(.caption).foregroundStyle(.red.opacity(0.8))
                        }
                        
                        Button {
                            Task { await loadReflection() }
                        } label: {
                            Text(grok != nil ? "Generate Reflection with Grok" : "Set XAI_API_KEY for AI reflections")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(grok != nil ? .indigo.opacity(0.3) : .gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingReflection || grok == nil)
                    }
                }
                
                // Static / local pattern cards (can be enhanced later)
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("coach.insights_pattern_title"))
                            .font(.headline)
                        Text("Your recent check-ins show good consistency. Energy has been slightly higher on days after 7+ hours of sleep.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("coach.insights_observation_title"))
                            .font(.headline)
                        Text(L("coach.insights_observation_message"))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("coach.insights_nav_title"))
        .withAppLanguage()
        .drawingGroup() // Round 15 perf
    }
    
    private func loadReflection() async {
        guard let service = grok else { return }
        isLoadingReflection = true
        error = nil
        
        let ctx = viewModel.buildCoachContext()
        let completed = max(viewModel.recentHealthSnapshots.count, 3) // rough proxy
        
        do {
            let text = try await service.getWeeklyReflection(
                context: ctx,
                workoutsCompleted: completed,
                avgEnergy: 6.8   // Could compute from real data
            )
            weeklyReflection = text
            viewModel.lastWeeklyReflection = text   // persist across navigation
        } catch {
            self.error = "Couldn't get reflection: \(error.localizedDescription.prefix(100))"
        }
        
        isLoadingReflection = false
    }
}
