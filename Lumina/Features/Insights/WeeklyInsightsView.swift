import SwiftUI
import SwiftData

struct WeeklyInsightsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    
    @State private var generatedTasks: [String] = []
    @State private var isGenerating = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("insights.this_week_title"))
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Week's Summary")
                            .font(.headline)
                        
                        Text("You completed \(viewModel.recentGoalAdjustments.count) coach-suggested actions recently. Review your saved notes.")
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Coach's Weekly Recommendations")
                            .font(.headline)
                        
                        if isGenerating {
                            HStack {
                                ProgressView()
                                Text("Analyzing your week...")
                            }
                        } else if generatedTasks.isEmpty {
                            Button("Generate Personalized Tasks") {
                                generateTasks()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            ForEach(generatedTasks, id: \.self) { task in
                                HStack {
                                    Text(task)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Button("Accept") {
                                        acceptTask(task)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.green)
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button("Regenerate Suggestions") {
                                generateTasks()
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("insights.nav_title"))
        .withAppLanguage()
        .drawingGroup() // Perf for insights cards
    }
    
    private func generateTasks() {
        isGenerating = true
        generatedTasks = []
        
        Task {
            let memory = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
            let context = viewModel.buildCoachContext()
            
            let prompt = """
            Based on this user's recent data and long-term memory, generate 3-4 very specific, actionable micro-tasks they can complete this week to move forward.
            Make them concrete and easy to start (not vague). One task per line.
            
            Strongly prefer tasks that:
            - Build on coach-suggested habits that are already showing early wins (energy, photos, consistency, recovery)
            - Or directly address coach habits where recent photo analysis (or cross-signal data) showed limited/no clear visible impact — e.g. "Review and adjust the 'evening walk' habit after limited photo evidence" or "Log a check-in + photo to measure the new protein habit"
            - Help measure / capture data on coach habits with activity but unclear or limited impact (e.g. "take a progress photo to check the new X habit")
            - Review recent coach photo analysis results, especially any that flagged limited progress on a coach-suggested habit
            
            Memory (includes explicit limited-impact and positive-outcome patterns from coach photo analyses):
            \(memory.prefix(700))
            """
            
            let apiKey = GrokService.configuredAPIKey ?? ""
            var tasks: [String] = []
            
            if !apiKey.isEmpty {
                let service = GrokService(apiKey: apiKey)
                if let response = try? await service.getSmartEmotionalSupport(
                    userMessage: prompt,
                    context: context,
                    longTermMemory: memory
                ) {
                    tasks = response.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
            
            if tasks.isEmpty {
                tasks = [
                    "Log a 15-minute walk today",
                    "Add one high-protein meal this week",
                    "Do one mobility session before bed 3x this week"
                ]
            }
            
            await MainActor.run {
                self.generatedTasks = tasks
                self.isGenerating = false
            }
        }
    }
    
    private func acceptTask(_ task: String) {
        // Turn the task into a real Goal
        let goal = Goal(
            name: task,
            currentValue: 0,
            targetValue: 1,
            unit: "completion",
            category: "weekly task"
        )
        guard viewModel.saveRecord(goal) else { return }
        
        // Remove from list
        generatedTasks.removeAll { $0 == task }
        
        // Round 81: Richer memory so coach tracks that the user acted on limited-impact photo findings or habit measurement tasks
        let lowerTask = task.lowercased()
        let memType: MemoryType = .pattern
        var memContent = "User accepted weekly coach task: \(task)"
        if lowerTask.contains("limited") || lowerTask.contains("review") || lowerTask.contains("adjust") || lowerTask.contains("photo") {
            memContent += " — directly addresses coach photo analysis showing limited impact or need for measurement on a coach-suggested habit"
        }
        viewModel.saveCoachMemoryEntry(type: memType, content: memContent)
        
        // Round 81 hygiene: Clear any pending coach photo outcome signals after accepting a weekly task (prevents stale reflection card)
        if viewModel.coachPhotoReflection != nil { viewModel.coachPhotoReflection = nil }
        if viewModel.pendingCoachPhotoAnalysis { viewModel.pendingCoachPhotoAnalysis = false }
        if viewModel.coachWantsProgressPhotoForHabit { viewModel.coachWantsProgressPhotoForHabit = false }
    }
}
