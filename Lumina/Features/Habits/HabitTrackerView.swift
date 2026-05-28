import SwiftUI
import SwiftData

struct HabitTrackerView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .reverse) private var habits: [Habit]
    
    @State private var showingNewHabit = false
    @State private var newHabitName = ""
    @State private var showingCoachSuggestions = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("habits.title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                
                // Coach Suggestions Section
                if !habits.filter({ $0.coachSuggested && $0.isActive }).isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text("Coach Recommended")
                                    .font(.headline)
                                    .foregroundStyle(.purple)
                            }
                            
                            // Round 82/86 polish: subtle outcome awareness for coach habits with limited impact (now uses cheap VM computed)
                            if viewModel.hasLimitedCoachHabitImpact {
                                Text("Coach noted limited impact on some suggestions — review in Progress Photos or chat.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            ForEach(habits.filter { $0.coachSuggested && $0.isActive }) { habit in
                                HabitRow(habit: habit, onToggle: { toggleHabit(habit) })
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // All Active Habits
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Habits")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if habits.filter({ $0.isActive }).isEmpty {
                        GlassCard {
                            Text("No habits yet. Ask your coach for personalized recommendations.")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal)
                    } else {
                        ForEach(habits.filter { $0.isActive && !$0.coachSuggested }) { habit in
                            GlassCard {
                                HabitRow(habit: habit, onToggle: { toggleHabit(habit) })
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                GlassButton(title: "Ask Coach for Habit Ideas", action: {
                    showingCoachSuggestions = true
                    Task {
                        await viewModel.generateCoachHabitSuggestions()
                    }
                })
                .padding(.horizontal)
                
                GlassButton(title: L("habits.add_button"), action: {
                    showingNewHabit = true
                })
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .glassBackground()
        .navigationTitle(L("tab.habits"))
        .withAppLanguage()
        .drawingGroup() // Perf: for list with coach cards
        .sheet(isPresented: $showingCoachSuggestions) {
            CoachHabitSuggestionsView()
        }
        .alert(L("habits.new_alert_title"), isPresented: $showingNewHabit) {
            TextField(L("habits.name_placeholder"), text: $newHabitName)
            Button(L("general.add")) {
                if !newHabitName.trimmingCharacters(in: .whitespaces).isEmpty {
                    let habit = Habit(name: newHabitName)
                    modelContext.insert(habit)
                    try? modelContext.save()
                    viewModel.invalidateHabitsCache()
                    newHabitName = ""
                }
            }
            Button(L("general.cancel"), role: .cancel) { newHabitName = "" }
        } message: {
            Text(L("habits.new_alert_message"))
        }
    }
    
    private func toggleHabit(_ habit: Habit) {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let last = habit.lastCompletedDate, Calendar.current.isDate(last, inSameDayAs: today) {
            // Undo today's completion
            habit.lastCompletedDate = Calendar.current.date(byAdding: .day, value: -1, to: today)
            habit.currentStreak = max(0, habit.currentStreak - 1)
            habit.totalCompletions -= 1
        } else {
            // Mark as done today
            habit.lastCompletedDate = today
            habit.totalCompletions += 1
            
            if let last = habit.lastCompletedDate {
                let daysSince = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
                if daysSince <= 1 {
                    habit.currentStreak += 1
                } else {
                    habit.currentStreak = 1
                }
            } else {
                habit.currentStreak = 1
            }
            
            habit.bestStreak = max(habit.bestStreak, habit.currentStreak)
        }
        
        try? modelContext.save()
        
        // Feed this data back to the coach
        Task {
            await viewModel.recordHabitCompletion(habit: habit)
            
            // Round 37: Intelligent adjustment suggestion if streak is low
            if habit.currentStreak == 0 && habit.coachSuggested {
                // Could trigger a suggestion to adjust frequency or replace habit
                await MainActor.run {
                    // For demo, add a note
                    habit.coachNotes = "Coach suggests trying a shorter version or pairing with existing habit for better consistency."
                }
            }
        }
    }
}

struct HabitRow: View {
    let habit: Habit
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(habit.name)
                    .foregroundStyle(.white)
                
                if habit.coachSuggested, let notes = habit.coachNotes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.purple.opacity(0.8))
                }
                
                HStack(spacing: 4) {
                    Text("\(habit.currentStreak) day streak")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    
                    if habit.coachSuggested {
                        Text("• Coach goal: \(habit.targetFrequencyPerWeek)x/week")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            Button(action: onToggle) {
                Image(systemName: isCompletedToday(habit) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompletedToday(habit) ? .green : .white.opacity(0.5))
                    .font(.title2)
            }
        }
    }
    
    private func isCompletedToday(_ habit: Habit) -> Bool {
        guard let last = habit.lastCompletedDate else { return false }
        return Calendar.current.isDate(last, inSameDayAs: Date())
    }
}

struct CoachHabitSuggestionsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Coach Habit Recommendations")
                            .font(.title.bold())
                        Spacer()
                        if !viewModel.coachHabitSuggestions.isEmpty {
                            Button("More ideas") {
                                Task {
                                    await viewModel.generateCoachHabitSuggestions()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal)
                    
                    if let added = viewModel.justAddedCoachHabit {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Added \"\(added)\" — great start! The coach is tracking how it helps.")
                                        .foregroundStyle(.white)
                                }
                                
                                // Round 58 polish + smarter loop: one-tap first win directly in sheet (highest leverage moment)
                                Button {
                                    // Save rich outcome-oriented memory immediately so coach sees the early action
                                    Task {
                                        await viewModel.saveCoachMemoryEntry(type: .pattern, content: "User logged first win on newly added coach habit: \(added). Suggest progress photo soon to measure impact.")
                                        await MainActor.run {
                                            viewModel.invalidateHabitsCache()
                                            viewModel.updateCoachFocusLiveActivity()
                                            // Round 59: clean any lingering follow-up UI when user takes the highest-leverage action
                                            viewModel.postActionCoachFollowUp = ""
                                            viewModel.showingPostActionFollowUp = false
                                        }
                                    }
                                    viewModel.justAddedCoachHabit = nil
                                    dismiss()
                                    // Brief global success so Home sees it too — strong photo bias for outcome tracking
                                    viewModel.followUpSuccessMessage = "First win on \(added) logged! Snap a progress photo soon to track the real impact."
                                } label: {
                                    Text("Log first win now (recommended)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(.green.opacity(0.35))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    if viewModel.coachHabitSuggestions.isEmpty && viewModel.justAddedCoachHabit == nil {
                        GlassCard {
                            Text("Analyzing your data... The coach will suggest habits that fit your current patterns and goals.")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal)
                    } 
                    
                    if !viewModel.coachHabitSuggestions.isEmpty {
                        ForEach(viewModel.coachHabitSuggestions, id: \.self) { suggestion in
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(suggestion)
                                        .foregroundStyle(.white)
                                    
                                    Button("Add This Habit") {
                                        viewModel.addCoachSuggestedHabit(name: suggestion, reason: "Suggested by coach based on your patterns")
                                        
                                        // Local immediate feedback via ViewModel signal (Round 48)
                                        // The VM method already sets justAddedCoachHabit + auto-clears it
                                        
                                        // Remove from suggestions
                                        viewModel.coachHabitSuggestions.removeAll { $0 == suggestion }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
                .drawingGroup() // Round 45 perf: coach habit suggestion cards
            }
            .glassBackground()
            .navigationTitle("Coach Suggestions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
