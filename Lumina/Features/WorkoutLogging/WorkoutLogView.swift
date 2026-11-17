import SwiftUI
import SwiftData

struct WorkoutLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LuminaViewModel.self) private var viewModel
    @State private var workoutName = ""
    @FocusState private var focusedTextField: WorkoutInputFocus?
    @State private var exercises: [WorkoutExerciseDraft] = []
    @State private var notes = ""
    @State private var rpe: Int? = nil
    @State private var showingSuccess = false
    @State private var showingHistory = false
    @State private var saveError: LocalRecordEditError?
    @State private var showingSaveError = false
    
    @Query(sort: \WorkoutLog.date, order: .reverse) private var recentLogs: [WorkoutLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(L("workout.log_title"))
                    .font(.largeTitle.bold())
                
                Button(L("View all saved workouts")) { showingHistory = true }
                    .accessibilityIdentifier("lumina.workout.history")
                if let saveError {
                    Text(saveError.localizedMessage).foregroundStyle(.primary)
                        .accessibilityIdentifier("lumina.workout.save-error")
                }

                // Round 34: Coach nudge in the logging flow (memory-aware)
                if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                    let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                    if mem.lowercased().contains("energy") || mem.lowercased().contains("recovery") || mem.lowercased().contains("consistent") {
                        GlassCard {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                                Text(L("Review your saved notes and record exertion if useful. Notes do not establish a health trend."))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }
                
                GlassCard {
                    TextField(L("workout.name_placeholder"), text: $workoutName)
                        .focused($focusedTextField, equals: .name)
                        .accessibilityIdentifier("lumina.workout.new-name")
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassCard {
                    Text(L("workout.exercises_label"))
                        .font(.headline)
                    
                    WorkoutExerciseFields(exercises: $exercises, focusedField: $focusedTextField)
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("workout.effort_optional"))
                            .font(.headline)
                        Picker(L("workout.effort_optional"), selection: $rpe) {
                            Text(L("workout.effort_not_recorded")).tag(Optional<Int>.none)
                            ForEach(1...10, id: \.self) { value in
                                Text(L("workout.effort_value", value)).tag(Optional(value))
                            }
                        }
                        .pickerStyle(.menu)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .labelsHidden()
                        .frame(minHeight: 44)
                        .accessibilityValue(rpe.map { L("workout.effort_value", $0) }
                            ?? L("workout.effort_not_recorded"))
                        .accessibilityHint(L("workout.effort_hint"))
                        .accessibilityIdentifier("lumina.workout.new-effort")
                        Text(L("workout.effort_hint"))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("lumina.workout.effort-scale")
                    }
                }
                
                GlassCard {
                    Text(L("workout.notes_label"))
                        .font(.headline)
                    TextField(L("workout.feel_placeholder"), text: $notes)
                        .focused($focusedTextField, equals: .notes)
                        .accessibilityIdentifier("lumina.workout.new-notes")
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassButton(title: L("workout.save_button"), isProminent: true, action: {
                    saveWorkout()
                })
                .accessibilityIdentifier("lumina.workout.new-save")
                .alert(L("Could not save workout"), isPresented: $showingSaveError) {
                    Button(L("OK")) { }
                } message: {
                    Text(saveError?.localizedMessage ?? L("Your workout draft has been kept. Please try again."))
                }
                
                if recentLogs.isEmpty {
                    Text(L("workout.empty_state"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                } else {
                    GlassCard {
                        Text(L("workout.recent_label"))
                            .font(.headline)
                        ForEach(recentLogs.prefix(3)) { log in
                            HStack {
                                Text(log.workoutName)
                                Spacer()
                                Text(log.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.workouts"))
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissalBar(isFocused: focusedTextField != nil) {
            focusedTextField = nil
        }
        .withAppLanguage()
        .sheet(isPresented: $showingHistory) {
            NavigationStack { WorkoutHistoryView() }
        }
        .alert(L("workout.saved_alert_title"), isPresented: $showingSuccess) {
            Button(L("general.ok")) { }
        } message: {
            Text(L("workout.saved_alert_message"))
        }
    }
    
    private func saveWorkout() {
        let cleanName: String
        let savedExercises: [LoggedExercise]
        do {
            cleanName = try LocalRecordDraft.name(workoutName, field: "a workout name")
            savedExercises = try exercises.map { try $0.validated() }
        } catch {
            saveError = (error as? LocalRecordEditError) ?? .invalid(error.localizedDescription)
            showingSaveError = true
            return
        }
        let log = WorkoutLog(workoutName: cleanName, exercises: savedExercises,
                             perceivedExertion: rpe, notes: notes.isEmpty ? nil : notes)
        guard viewModel.saveRecord(log) else {
            saveError = .invalid(viewModel.errorMessage ?? "Could not save the workout. Your draft has been kept.")
            viewModel.errorMessage = nil
            showingSaveError = true
            return
        }
        saveError = nil
        
        viewModel.invalidateWorkoutsCache()

        // Round 37: Update Live Activity dynamically after workout log + feed coach
        viewModel.updateCoachFocusLiveActivity()
        let effortNote = log.perceivedExertion.map { " with RPE \($0)" } ?? ""
        viewModel.saveCoachMemoryEntry(type: .pattern,
            content: "Logged workout: \(log.workoutName)\(effortNote)")
        
        // Reset form
        workoutName = ""
        exercises = []
        notes = ""
        rpe = nil
        showingSuccess = true
    }
}

