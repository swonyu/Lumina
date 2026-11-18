import SwiftUI
import SwiftData

/// Editors hold their own draft. Cancel never writes to the persisted model.
private struct RecordEditorForm<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var showingOperationError = false
    @State private var operationErrorTitle = "Could not save this record"
    let title: String
    let error: String?
    let save: () -> Bool
    var delete: (() -> Bool)? = nil
    let content: Content

    init(title: String, error: String?, save: @escaping () -> Bool,
         delete: (() -> Bool)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.error = error
        self.save = save
        self.delete = delete
        self.content = content()
    }

    var body: some View {
        Form {
            content
            if let error {
                Section { Label(L(error), systemImage: "exclamationmark.circle")
                    .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lumina.record.edit-error") }
            }
            if delete != nil {
                Section {
                    Button(L("Delete this record"), role: .destructive) { confirmingDeletion = true }
                }
            }
        }
        .navigationTitle(L(title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save")) {
                    if save() { dismiss() } else {
                        operationErrorTitle = "Could not save this record"
                        showingOperationError = true
                    }
                }
                    .accessibilityIdentifier("lumina.record.save")
            }
        }
        .alert(L(operationErrorTitle), isPresented: $showingOperationError) {
            Button(L("OK")) { }
        } message: {
            Text(L(error ?? "Your draft has been kept. Please check the fields and try again."))
        }
        .confirmationDialog(L("Delete this record?"), isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(L("Delete record"), role: .destructive) {
                if delete?() == true { dismiss() } else {
                    operationErrorTitle = "Could not delete this record"
                    showingOperationError = true
                }
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("This cannot be undone. Other records and exported backups are kept. Saved coaching notes may still mention this record; Delete all local data removes those notes too."))
        }
    }
}

struct JournalRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let entry: JournalEntry
    @State private var draft: JournalEditDraft
    @State private var error: String?

    init(entry: JournalEntry) {
        self.entry = entry
        _draft = State(initialValue: JournalEditDraft(entry))
    }

    var body: some View {
        RecordEditorForm(title: "Journal entry", error: error, save: save, delete: remove) {
            Section(L("Entry")) {
                DatePicker(L("Recorded at"), selection: $draft.date)
                TextField(L("Title (optional)"), text: $draft.title)
                TextEditor(text: $draft.content).frame(minHeight: 240)
                    .accessibilityLabel(L("Full journal entry"))
                    .accessibilityIdentifier("lumina.journal.full-content")
                Menu {
                    Picker(L("Mood"), selection: $draft.mood) {
                        Text(L("Not recorded")).tag(Mood?.none)
                        ForEach(Mood.allCases, id: \.self) { value in Text(L(value.rawValue)).tag(Optional(value)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack {
                        Text(L("Mood"))
                        Spacer()
                        Text(draft.mood.map { L($0.rawValue) } ?? L("Not recorded"))
                        Image(systemName: "chevron.up.chevron.down")
                            .accessibilityHidden(true)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                .accessibilityLabel(L("Mood"))
                .accessibilityValue(draft.mood.map { L($0.rawValue) } ?? L("Not recorded"))
                .accessibilityIdentifier("lumina.journal.record-mood")
            }
            if !entry.tags.isEmpty {
                Section(L("Saved tags")) { Text(entry.tags.joined(separator: ", ")) }
            }
        }
    }

    private func save() -> Bool {
        do { try draft.save(to: entry, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        do { try viewModel.deleteLocalRecord(entry); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct GoalRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let goal: Goal?
    @State private var draft: GoalEditDraft
    @State private var error: String?

    init(goal: Goal? = nil) {
        self.goal = goal
        _draft = State(initialValue: GoalEditDraft(goal))
    }

    var body: some View {
        RecordEditorForm(title: editorTitle, error: error, save: save, delete: deleteAction) {
            goalFields
            savedAdjustmentNote
        }
    }

    private var editorTitle: String {
        goal == nil ? "New goal" : "Edit goal"
    }

    private var deleteAction: (() -> Bool)? {
        guard goal != nil else { return nil }
        return { remove() }
    }

    private var goalFields: some View {
        Section(L("Your goal")) {
            TextField(L("Goal name"), text: $draft.name).accessibilityIdentifier("lumina.goal.name")
            VStack(alignment: .leading, spacing: 6) {
                RecordFieldLabel(title: "Current value", identifier: "lumina.goal.current-label")
                TextField(L("Current value"), text: $draft.current).keyboardType(.decimalPad)
                    .accessibilityLabel(L("Current value"))
                    .accessibilityIdentifier("lumina.goal.current")
            }
            VStack(alignment: .leading, spacing: 6) {
                RecordFieldLabel(title: "Target value", identifier: "lumina.goal.target-label")
                TextField(L("Target value"), text: $draft.target).keyboardType(.decimalPad)
                    .accessibilityLabel(L("Target value"))
                    .accessibilityIdentifier("lumina.goal.target")
            }
            TextField(L("Unit"), text: $draft.unit)
            TextField(L("Category"), text: $draft.category)
            Text(L("Enter your own current value and a positive target. The ratio is a record of those numbers; Lumina does not measure progress for you."))
                .font(.caption)
        }
    }

    @ViewBuilder
    private var savedAdjustmentNote: some View {
        if let notes = goal?.adjustmentNotes {
            Section(L("Saved adjustment note")) {
                Text(notes).fixedSize(horizontal: false, vertical: true)
                if let date = goal?.lastAdjustedByCoach { Text(date.formatted()).font(.caption) }
            }
        }
    }

    private func save() -> Bool {
        do { try draft.save(to: goal, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        guard let goal else { return false }
        do { try viewModel.deleteLocalRecord(goal); viewModel.loadGoals(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

/// A separate visible label remains when the field contains a saved value.
/// The native text field keeps its original binding, focus and accessible name.
private struct RecordFieldLabel: View {
    let title: String
    let identifier: String

    var body: some View {
        Text(L(title))
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}

/// Native text fields retain each string draft until validated on explicit Save.
/// The same fields are used for new workouts and saved workout editing.
struct WorkoutExerciseFields: View {
    @Binding var exercises: [WorkoutExerciseDraft]
    let focusedField: FocusState<WorkoutInputFocus?>.Binding

    var body: some View {
        if exercises.isEmpty { Text(L("No exercises recorded.")).foregroundStyle(.secondary) }
        ForEach($exercises) { $exercise in
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("Exercise name"), text: $exercise.name)
                    .focused(focusedField, equals: .exercise(exercise.id))
                    .accessibilityLabel(L("Exercise name"))
                    .accessibilityIdentifier("lumina.workout.exercise.\(exercise.id.uuidString).name")
                ForEach($exercise.sets) { $set in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            RecordFieldLabel(title: "Repetitions",
                                             identifier: "lumina.workout.set.\(set.id.uuidString).repetitions-label")
                            TextField(L("Repetitions"), text: $set.repetitions).keyboardType(.numberPad)
                                .focused(focusedField, equals: .repetitions(set.id))
                                .accessibilityLabel(L("Repetitions for %@", exercise.name))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            RecordFieldLabel(title: "Weight in kilograms (optional)",
                                             identifier: "lumina.workout.set.\(set.id.uuidString).weight-label")
                            TextField(L("Weight in kilograms (optional)"), text: $set.weight).keyboardType(.decimalPad)
                                .focused(focusedField, equals: .weight(set.id))
                                .accessibilityLabel(L("Weight in kilograms for %@", exercise.name))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            RecordFieldLabel(title: "Set exertion 1–10 (optional)",
                                             identifier: "lumina.workout.set.\(set.id.uuidString).exertion-label")
                            TextField(L("Set exertion 1–10 (optional)"), text: $set.exertion).keyboardType(.numberPad)
                                .focused(focusedField, equals: .exertion(set.id))
                                .accessibilityLabel(L("Set exertion for %@", exercise.name))
                        }
                        Button(L("Remove set"), role: .destructive) {
                            exercise.sets.removeAll { $0.id == set.id }
                        }
                        .accessibilityLabel(L("Remove set from %@", exercise.name))
                    }
                    .padding(.vertical, 4)
                }
                Button(L("Add set")) { exercise.sets.append(WorkoutSetDraft()) }
                Button(L("Remove exercise"), role: .destructive) {
                    exercises.removeAll { $0.id == exercise.id }
                }
            }
            .padding(.vertical, 4)
        }
        Button(L("Add exercise")) { exercises.append(WorkoutExerciseDraft()) }

    }
}

struct WorkoutRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let log: WorkoutLog
    @State private var draft: WorkoutEditDraft
    @State private var error: String?
    @FocusState private var focusedField: WorkoutInputFocus?

    init(log: WorkoutLog) {
        self.log = log
        _draft = State(initialValue: WorkoutEditDraft(log))
    }

    var body: some View {
        RecordEditorForm(title: "Saved workout", error: error, save: save, delete: remove) {
            Section(L("Workout")) {
                TextField(L("Workout name"), text: $draft.name)
                    .focused($focusedField, equals: .name)
                    .accessibilityIdentifier("lumina.workout.record-name")
                DatePicker(L("Recorded at"), selection: $draft.date)
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Exertion 1–10 (optional)",
                                     identifier: "lumina.workout.record-effort-label")
                    TextField(L("Exertion 1–10 (optional)"), text: $draft.exertion).keyboardType(.numberPad)
                        .focused($focusedField, equals: .workoutExertion)
                        .accessibilityLabel(L("Exertion 1–10 (optional)"))
                        .accessibilityIdentifier("lumina.workout.record-effort")
                }
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Duration in minutes (optional)",
                                     identifier: "lumina.workout.record-duration-label")
                    TextField(L("Duration in minutes (optional)"), text: $draft.duration).keyboardType(.numberPad)
                        .focused($focusedField, equals: .duration)
                }
                TextEditor(text: $draft.notes).frame(minHeight: 120).accessibilityLabel(L("Workout notes"))
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("lumina.workout.record-notes")
            }
            Section(L("Exercises and sets")) { WorkoutExerciseFields(exercises: $draft.exercises, focusedField: $focusedField) }
        }
        .keyboardDismissalBar(isFocused: focusedField != nil) { focusedField = nil }
    }

    private func save() -> Bool {
        do { try draft.save(to: log, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        do { try viewModel.deleteLocalRecord(log); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct MealRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let meal: MealLog
    @State private var draft: MealEditDraft
    @State private var error: String?

    init(meal: MealLog) {
        self.meal = meal
        _draft = State(initialValue: MealEditDraft(meal))
    }

    var body: some View {
        RecordEditorForm(title: "Saved meal", error: error, save: save, delete: remove) {
            Section(L("Meal")) {
                TextField(L("Meal name"), text: $draft.name).accessibilityIdentifier("lumina.meal.record-name")
                DatePicker(L("Recorded at"), selection: $draft.date)
                TextEditor(text: $draft.notes).frame(minHeight: 120).accessibilityLabel(L("Meal notes"))
                    .accessibilityIdentifier("lumina.meal.record-notes")
            }
            Section(L("Your nutrition entries (optional)")) {
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Calories",
                                     identifier: "lumina.meal.record-calories-label")
                    TextField(L("Calories"), text: $draft.calories).keyboardType(.decimalPad)
                        .accessibilityLabel(L("Calories"))
                        .accessibilityIdentifier("lumina.meal.record-calories")
                }
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Protein in grams",
                                     identifier: "lumina.meal.record-protein-label")
                    TextField(L("Protein in grams"), text: $draft.protein).keyboardType(.decimalPad)
                        .accessibilityLabel(L("Protein in grams"))
                        .accessibilityIdentifier("lumina.meal.record-protein")
                }
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Carbohydrates in grams",
                                     identifier: "lumina.meal.record-carbs-label")
                    TextField(L("Carbohydrates in grams"), text: $draft.carbs).keyboardType(.decimalPad)
                }
                VStack(alignment: .leading, spacing: 6) {
                    RecordFieldLabel(title: "Fat in grams",
                                     identifier: "lumina.meal.record-fat-label")
                    TextField(L("Fat in grams"), text: $draft.fat).keyboardType(.decimalPad)
                }
                Text(L("Leave a field empty if it was not recorded. These are your entries; Lumina does not estimate them from the photo."))
                    .font(.caption)
            }
            if let photoData = draft.photoData {
                Section(L("Saved photo")) {
                    if let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel(L("Saved photo of %@", draft.name))
                            .accessibilityIdentifier("lumina.meal.saved-photo")
                    } else {
                        Text(L("This saved photo could not be displayed. Its original data is kept unless you remove it."))
                    }
                    Button(L("Remove saved photo"), role: .destructive) { draft.photoData = nil }
                }
            }
        }
    }

    private func save() -> Bool {
        do { try draft.save(to: meal, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        do { try viewModel.deleteLocalRecord(meal); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct CheckInRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let checkIn: DailyCheckIn
    @State private var draft: CheckInEditDraft
    @State private var error: String?

    init(checkIn: DailyCheckIn) {
        self.checkIn = checkIn
        _draft = State(initialValue: CheckInEditDraft(checkIn))
    }

    var body: some View {
        RecordEditorForm(title: "Saved check-in", error: error, save: save, delete: remove) {
            Section(L("Your ratings")) {
                DatePicker(L("Recorded at"), selection: $draft.date)
                Stepper(L("Energy: %d/10", draft.energy), value: $draft.energy, in: 1...10)
                Stepper(L("Soreness: %d/10", draft.soreness), value: $draft.soreness, in: 1...10)
                Stepper(L("Sleep quality: %d/10", draft.sleep), value: $draft.sleep, in: 1...10)
                Stepper(L("Stress: %d/10", draft.stress), value: $draft.stress, in: 1...10)
                Picker(L("Mood"), selection: $draft.mood) {
                    ForEach(Mood.allCases, id: \.self) { Text(L($0.rawValue)).tag($0) }
                }
                Toggle(L("Trained that day"), isOn: $draft.didTrain)
            }
            Section(L("Your note")) {
                TextEditor(text: $draft.note).frame(minHeight: 180).accessibilityLabel(L("Check-in note"))
                    .accessibilityIdentifier("lumina.checkin.record-note")
            }
        }
    }

    private func save() -> Bool {
        do { try draft.save(to: checkIn, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        do { try viewModel.deleteLocalRecord(checkIn); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct HabitRecordEditor: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let habit: Habit
    @State private var draft: HabitEditDraft
    @State private var error: String?

    init(habit: Habit) {
        self.habit = habit
        _draft = State(initialValue: HabitEditDraft(habit))
    }

    var body: some View {
        RecordEditorForm(title: "Edit habit", error: error, save: save, delete: remove) {
            Section(L("Habit")) {
                TextField(L("Habit name"), text: $draft.name).accessibilityIdentifier("lumina.habit.record-name")
                Toggle(L("Active"), isOn: $draft.active)
                Stepper(L("Target: %d days per week", draft.frequency), value: $draft.frequency, in: 1...7)
                Text(L("Inactive habits keep their saved counters and stop appearing in the active list."))
                    .font(.caption)
            }
            Section(L("Saved activity")) {
                Text(L("Total recorded completions: %d", habit.totalCompletions))
                Text(L("Last recorded streak: %d days", habit.currentStreak))
                Text(L("Best recorded streak: %d days", habit.bestStreak))
                if let date = habit.lastCompletedDate { Text(L("Last completed: %@", date.formatted())) }
                if let notes = habit.coachNotes { Text(notes).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private func save() -> Bool {
        do { try draft.save(to: habit, using: viewModel); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func remove() -> Bool {
        do { try viewModel.deleteLocalRecord(habit); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}


struct NewHabitRecordView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        RecordEditorForm(title: "New habit", error: error, save: save) {
            Section(L("Your habit")) {
                TextField(L("Habit name"), text: $name)
                    .accessibilityIdentifier("lumina.habit.new-name")
                Text(L("Choose a habit name. Adding it does not record a completion."))
                    .font(.caption)
            }
        }
    }
    private func save() -> Bool {
        guard viewModel.addLocalHabit(name: name) else {
            error = viewModel.errorMessage ?? "Could not save the habit. Your draft has been kept."
            viewModel.errorMessage = nil
            return false
        }
        return true
    }
}
