import SwiftUI
import SwiftData

struct WorkoutLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LuminaViewModel.self) private var viewModel
    @State private var workoutName = ""
    @State private var exercises: [LoggedExercise] = []
    @State private var notes = ""
    @State private var rpe: Int = 7
    @State private var showingSuccess = false
    
    @Query(sort: \WorkoutLog.date, order: .reverse) private var recentLogs: [WorkoutLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(L("workout.log_title"))
                    .font(.largeTitle.bold())
                
                // Round 34: Coach nudge in the logging flow (memory-aware)
                if !viewModel.smartMemorySummary.isEmpty || !viewModel.memorySummary.isEmpty {
                    let mem = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.memorySummary
                    if mem.lowercased().contains("energy") || mem.lowercased().contains("recovery") || mem.lowercased().contains("consistent") {
                        GlassCard {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                                Text("Coach note: Recent patterns suggest logging perceived exertion and notes carefully today.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }
                
                GlassCard {
                    TextField(L("workout.name_placeholder"), text: $workoutName)
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassCard {
                    Text(L("workout.exercises_label"))
                        .font(.headline)
                    
                    if exercises.isEmpty {
                        Text(L("workout.no_exercises"))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    ForEach($exercises) { $exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField("Exercise name", text: $exercise.name)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button {
                                    if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
                                        exercises.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            HStack {
                                Text(L("workout.sets_count", exercise.sets.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    exercise.sets.append(LoggedSet(reps: 8, weight: 0))
                                } label: {
                                    Label(L("workout.add_set"), systemImage: "plus.circle")
                                        .font(.caption)
                                }
                            }
                            
                            ForEach($exercise.sets) { $set in
                                HStack {
                                    Text(L("workout.set_label"))
                                    TextField(L("workout.reps_placeholder"), value: $set.reps, format: .number)
                                        .frame(width: 50)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Text(L("workout.reps_at"))
                                    TextField(L("workout.kg_placeholder"), value: $set.weight.boundToZero, format: .number)
                                    .frame(width: 55)
                                    .textFieldStyle(.roundedBorder)
                                    Text(L("workout.kg_unit"))
                                    
                                    Button {
                                        if let index = exercise.sets.firstIndex(where: { $0.id == set.id }) {
                                            exercise.sets.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button(L("workout.add_exercise")) {
                        exercises.append(LoggedExercise(name: "New Exercise", sets: []))
                    }
                    .buttonStyle(.bordered)
                }
                
                GlassCard {
                    Stepper(L("workout.rpe_label", rpe), value: $rpe, in: 1...10)
                }
                
                GlassCard {
                    Text(L("workout.notes_label"))
                        .font(.headline)
                    TextField(L("workout.feel_placeholder"), text: $notes)
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassButton(title: L("workout.save_button"), isProminent: true, action: {
                    saveWorkout()
                })
                
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
        .withAppLanguage()
        .alert(L("workout.saved_alert_title"), isPresented: $showingSuccess) {
            Button(L("general.ok")) { }
        } message: {
            Text(L("workout.saved_alert_message"))
        }
    }
    
    private func saveWorkout() {
        guard !workoutName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let log = WorkoutLog(workoutName: workoutName, exercises: exercises, perceivedExertion: rpe, notes: notes.isEmpty ? nil : notes)
        modelContext.insert(log)
        try? modelContext.save()
        
        // Round 37: Update Live Activity dynamically after workout log + feed coach
        Task {
            await viewModel.updateCoachFocusLiveActivity()
            await MainActor.run {
                viewModel.saveCoachMemoryEntry(type: .pattern, content: "Logged workout: \(workoutName) with RPE \(rpe)")
            }
        }
        
        // Reset form
        workoutName = ""
        exercises = []
        notes = ""
        rpe = 7
        showingSuccess = true
    }
}

// MARK: - Optional Binding Helper (cleans up weight editing)
extension Binding where Value == Double? {
    var boundToZero: Binding<Double> {
        Binding<Double>(
            get: { self.wrappedValue ?? 0 },
            set: { self.wrappedValue = $0 }
        )
    }
}
