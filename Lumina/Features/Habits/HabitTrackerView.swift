import SwiftUI
import SwiftData

struct HabitTrackerView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt, order: .reverse) private var habits: [Habit]
    
    @State private var showingHistory = false
    @State private var showingNewHabit = false
    @State private var showingCoachSuggestions = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("habits.title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                
                Button(L("Manage saved habits")) { showingHistory = true }
                    .accessibilityIdentifier("lumina.habit.history")
                    .padding(.horizontal)

                // Coach Suggestions Section
                if !habits.filter({ $0.coachSuggested && $0.isActive }).isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text(L("Suggested habits"))
                                    .font(.headline)
                                    .foregroundStyle(.purple)
                            }
                            
                            // Round 82/86 polish: subtle outcome awareness for coach habits with limited impact (now uses cheap VM computed)
                            if viewModel.hasLimitedCoachHabitImpact {
                                Text(L("Saved coach notes may contain earlier prototype claims. Review them as notes, not measured outcomes."))
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
                    Text(L("Your Habits"))
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if habits.filter({ $0.isActive }).isEmpty {
                        GlassCard {
                            Text(L("No habits yet. Add one or browse general habit ideas."))
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
                
                GlassButton(title: L("Browse habit ideas"), action: {
                    showingCoachSuggestions = true
                    Task {
                        await viewModel.generateCoachHabitSuggestions()
                    }
                })
                .padding(.horizontal)
                
                GlassButton(title: L("habits.add_button"), action: {
                    showingNewHabit = true
                })
                .accessibilityIdentifier("lumina.habit.add")
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .glassBackground()
        .navigationTitle(L("tab.habits"))
        .withAppLanguage()
        .sheet(isPresented: $showingHistory) {
            NavigationStack { HabitHistoryView() }
        }
        .sheet(isPresented: $showingCoachSuggestions) {
            CoachHabitSuggestionsView()
        }
        .sheet(isPresented: $showingNewHabit) {
            NavigationStack { NewHabitRecordView() }
        }
    }
    
    private func toggleHabit(_ habit: Habit) {
        do {
            try viewModel.commitLocalEdit { habit.toggleCompletion() }
        } catch {
            viewModel.errorMessage = L("Could not save habit completion: %@", error.localizedDescription)
            return
        }

        Task { await viewModel.recordHabitCompletion(habit: habit) }
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
                    Text(L("Last recorded streak: %d days", habit.currentStreak))
                        .font(.caption2)
                        .foregroundStyle(.green)
                    
                    if habit.coachSuggested {
                        Text(L("• Target: %d times/week", habit.targetFrequencyPerWeek))
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
            .accessibilityLabel(isCompletedToday(habit)
                ? L("Undo today's completion for %@", habit.name)
                : L("Mark %@ complete for today", habit.name))
            .accessibilityValue(L(isCompletedToday(habit) ? "Completed today" : "Not completed today"))
            .accessibilityHint(L(isCompletedToday(habit)
                ? "Removes today's completion and updates the recorded streak."
                : "Records one completion for today and updates the recorded streak."))
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
    @State private var saveError: String?
    @AccessibilityFocusState private var saveErrorFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L("Habit ideas"))
                            .font(.title.bold())
                        Spacer()
                        if !viewModel.coachHabitSuggestions.isEmpty {
                            Button(L("More ideas")) {
                                Task {
                                    await viewModel.generateCoachHabitSuggestions()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal)

                    if let saveError {
                        Label(L(saveError), systemImage: "exclamationmark.circle")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("lumina.habit.save-error")
                            .accessibilityFocused($saveErrorFocused)
                            .padding(.horizontal)
                    }
                    
                    if let added = viewModel.justAddedCoachHabit {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(L("Added \"%@\" to your habits.", added))
                                        .foregroundStyle(.white)
                                }
                                
                                Text(L("Use the habit's completion button after you finish it."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    if viewModel.coachHabitSuggestions.isEmpty && viewModel.justAddedCoachHabit == nil {
                        GlassCard {
                            Text(L("No more general ideas to show. You can add your own habit."))
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
                                    
                                    Button(L("Add This Habit")) {
                                        guard viewModel.addCoachSuggestedHabit(name: suggestion,
                                            reason: L("Selected from general habit ideas")) else {
                                            saveError = viewModel.errorMessage ?? "Could not add the habit. Please try again."
                                            viewModel.errorMessage = nil
                                            saveErrorFocused = true
                                            return
                                        }
                                        saveError = nil
                                        saveErrorFocused = false
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
            }
            .glassBackground()
            .navigationTitle(L("Habit ideas"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
