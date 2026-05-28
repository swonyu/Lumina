import SwiftUI
import SwiftData

struct WorkoutLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var workoutName = ""
    @State private var exercises: [LoggedExercise] = []
    @State private var notes = ""
    @State private var rpe: Int = 7
    @State private var showingSuccess = false
    
    @Query(sort: \WorkoutLog.date, order: .reverse) private var recentLogs: [WorkoutLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Log Workout")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    TextField("Workout Name", text: $workoutName)
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassCard {
                    Text("Exercises")
                        .font(.headline)
                    
                    if exercises.isEmpty {
                        Text("No exercises yet")
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
                                Text("\(exercise.sets.count) sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    exercise.sets.append(LoggedSet(reps: 8, weight: 0))
                                } label: {
                                    Label("Add Set", systemImage: "plus.circle")
                                        .font(.caption)
                                }
                            }
                            
                            ForEach($exercise.sets) { $set in
                                HStack {
                                    Text("Set:")
                                    TextField("Reps", value: $set.reps, format: .number)
                                        .frame(width: 50)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Text("reps @")
                                    TextField("kg", value: $set.weight.boundToZero, format: .number)
                                    .frame(width: 55)
                                    .textFieldStyle(.roundedBorder)
                                    Text("kg")
                                    
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
                    
                    Button("Add Exercise") {
                        exercises.append(LoggedExercise(name: "New Exercise", sets: []))
                    }
                    .buttonStyle(.bordered)
                }
                
                GlassCard {
                    Stepper("RPE: \(rpe)", value: $rpe, in: 1...10)
                }
                
                GlassCard {
                    Text("Notes")
                        .font(.headline)
                    TextField("How did it feel?", text: $notes)
                        .textFieldStyle(.roundedBorder)
                }
                
                GlassButton(title: "Save Workout", isProminent: true) {
                    saveWorkout()
                }
                
                if recentLogs.isEmpty {
                    Text("No workouts logged yet. Start building your history!")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                } else {
                    GlassCard {
                        Text("Recent Workouts")
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
        .navigationTitle("Workouts")
        .alert("Workout saved!", isPresented: $showingSuccess) {
            Button("OK") { }
        } message: {
            Text("Great work. Your coach will factor this in.")
        }
    }
    
    private func saveWorkout() {
        guard !workoutName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let log = WorkoutLog(workoutName: workoutName, exercises: exercises, perceivedExertion: rpe, notes: notes.isEmpty ? nil : notes)
        modelContext.insert(log)
        try? modelContext.save()
        
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
