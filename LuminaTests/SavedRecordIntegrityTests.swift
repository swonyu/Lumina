import Foundation
import SwiftData
import Testing
@testable import Lumina

@MainActor
struct SavedRecordIntegrityTests {
    @Test func activeHabitUniquenessIncludesOlderRecordsAndBothAddPaths() throws {
        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldest = Habit(name: "  Evening walk\n")
        oldest.createdAt = Date(timeIntervalSince1970: 10)
        #expect(model.saveRecord(oldest))
        for n in 0..<8 {
            let habit = Habit(name: "Other habit \(n)")
            habit.createdAt = Date(timeIntervalSince1970: Double(100 + n))
            #expect(model.saveRecord(habit))
        }
        #expect(model.activeHabits.count == 6)
        #expect(!model.activeHabits.contains { $0.id == oldest.id })
        #expect(!model.addLocalHabit(name: "EVENING WALK"))
        #expect(!model.addCoachSuggestedHabit(name: "\nevening WALK  "))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Habit>()) == 9)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<CoachMemoryEntry>()) == 0)
        #expect(model.justAddedCoachHabit == nil && model.followUpSuccessMessage.isEmpty)
        #expect(!model.addLocalHabit(name: " \n\t"))
        #expect(model.addLocalHabit(name: "  Read before bed\n"))
        let reopened = try reopen(directory)
        let habits = try reopened.mainContext.fetch(FetchDescriptor<Habit>())
        #expect(habits.count == 10)
        let added = try #require(habits.first { $0.name == "Read before bed" })
        #expect(added.totalCompletions == 0 && added.lastCompletedDate == nil)
    }

    @Test func habitEditsPreserveCountersAndRejectDuplicateReactivation() throws {
        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let habit = Habit(name: "Walking", coachSuggested: true)
        habit.totalCompletions = 23
        habit.currentStreak = 4
        habit.bestStreak = 9
        habit.lastCompletedDate = Date(timeIntervalSince1970: 1_700_000_000)
        habit.coachNotes = "Saved historical note"
        #expect(model.saveRecord(habit))
        var draft = HabitEditDraft(habit)
        draft.name = "  Evening walking  "
        draft.frequency = 4
        try draft.save(to: habit, using: model)
        #expect(habit.name == "Evening walking" && habit.targetFrequencyPerWeek == 4)
        #expect(habit.totalCompletions == 23 && habit.currentStreak == 4 && habit.bestStreak == 9)
        #expect(habit.lastCompletedDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(habit.coachSuggested && habit.coachNotes == "Saved historical note")
        draft.active = false
        try draft.save(to: habit, using: model)
        #expect(!habit.isActive)
        #expect(model.addLocalHabit(name: "EVENING WALKING"))
        draft.active = true
        #expect(throws: LocalRecordEditError.self) { try draft.save(to: habit, using: model) }
        #expect(!habit.isActive && habit.totalCompletions == 23)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func canceledDraftsDoNotWriteOrLoseSavedPhotoAndSetData() throws {
        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = JournalEntry(content: "Full saved journal\nSecond line\nThird line\nFourth line retained")
        let meal = MealLog(mealName: "Saved meal", notes: "Original", photoData: Data([10, 20, 30]))
        let workout = WorkoutLog(workoutName: "Saved workout", exercises: [LoggedExercise(name: "Squat", sets: [LoggedSet(reps: 5, weight: 20, rpe: 7)])])
        container.mainContext.insert(journal)
        container.mainContext.insert(meal)
        container.mainContext.insert(workout)
        try container.mainContext.save()
        var journalDraft = JournalEditDraft(journal);journalDraft.content = "Unsaved replacement"
        var mealDraft = MealEditDraft(meal);mealDraft.name = "Unsaved";mealDraft.photoData = nil
        var workoutDraft = WorkoutEditDraft(workout);workoutDraft.exercises[0].sets[0].repetitions = "99"
        // Simulate an autosave boundary while the edit drafts still exist.
        try container.mainContext.save()
        let fresh = try reopen(directory)
        #expect(try fresh.mainContext.fetch(FetchDescriptor<JournalEntry>()).first?.content == journal.content)
        #expect(try fresh.mainContext.fetch(FetchDescriptor<MealLog>()).first?.photoData == Data([10, 20, 30]))
        #expect(try fresh.mainContext.fetch(FetchDescriptor<MealLog>()).first?.mealName == "Saved meal")
        #expect(try fresh.mainContext.fetch(FetchDescriptor<WorkoutLog>()).first?.exercises.first?.sets.first?.reps == 5)
        #expect(journalDraft.content == "Unsaved replacement" && mealDraft.photoData == nil)
        #expect(workoutDraft.exercises[0].sets[0].repetitions == "99")
        #expect(!model.modelContext.hasChanges)
    }

    @Test func savedEditsRoundTripAllFieldsAndKeepIdentitiesOwners() throws {
        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let user = UserProfile(name: "Local fixture", age: 30, gender: .other, heightCm: 170, currentWeightKg: 70,
            experienceLevel: .beginner, primaryGoal: .generalHealth, workoutDaysPerWeek: 2, equipmentAccess: .none)
        let journal = JournalEntry(content: "Original", tags: ["kept", "fixture"])
        let meal = MealLog(mealName: "Original meal", photoData: Data([1, 3, 5, 7]))
        let workout = WorkoutLog(workoutName: "Original workout", exercises: [LoggedExercise(name: "Squat", sets: [LoggedSet(reps: 5, weight: 20, rpe: 7)])])
        let goal = Goal(name: "Original goal", currentValue: 1, targetValue: 5)
        goal.adjustmentNotes = "Legacy note kept";goal.lastAdjustedByCoach = Date(timeIntervalSince1970: 20)
        let checkIn = DailyCheckIn(energyLevel: 5, sorenessLevel: 3, sleepQuality: 6, stressLevel: 4, mood: .good)
        container.mainContext.insert(user)
        container.mainContext.insert(journal);container.mainContext.insert(meal)
        container.mainContext.insert(workout);container.mainContext.insert(goal);container.mainContext.insert(checkIn)
        journal.owner=user;meal.owner=user;workout.owner=user;goal.owner=user;checkIn.owner=user
        try container.mainContext.save()
        let ids=[journal.id,meal.id,workout.id,goal.id,checkIn.id]
        let exerciseID=workout.exercises[0].id;let setID=workout.exercises[0].sets[0].id
        let date=Date(timeIntervalSince1970: 1_700_000_100)
        var j=JournalEditDraft(journal);j.title="Full entry";j.content="Line1\nLine2\nLine3\nLine4\nLast exact line";j.mood = .good;j.date=date
        try j.save(to: journal,using: model)
        var m=MealEditDraft(meal);m.name="Edited meal";m.date=date;m.calories="430.5";m.protein="24.5";m.carbs="50";m.fat="12";m.notes="Full nutrition notes"
        try m.save(to: meal,using: model)
        var w=WorkoutEditDraft(workout);w.name="Edited workout";w.date=date;w.notes="Full workout notes";w.duration="45";w.exertion="8";w.exercises[0].sets[0].repetitions="8";w.exercises[0].sets[0].weight="25.5"
        try w.save(to: workout,using: model)
        var g=GoalEditDraft(goal);g.name="Edited goal";g.current="3";g.target="8";g.unit="sessions";g.category="personal"
        try g.save(to: goal,using: model)
        var c=CheckInEditDraft(checkIn);c.date=date;c.energy=7;c.soreness=2;c.sleep=8;c.stress=3;c.note="Complete check-in note";c.didTrain=true
        try c.save(to: checkIn,using: model)
        let fresh=try reopen(directory);let context=fresh.mainContext
        let jj=try #require(context.fetch(FetchDescriptor<JournalEntry>()).first)
        let mm=try #require(context.fetch(FetchDescriptor<MealLog>()).first)
        let ww=try #require(context.fetch(FetchDescriptor<WorkoutLog>()).first)
        let gg=try #require(context.fetch(FetchDescriptor<Goal>()).first)
        let cc=try #require(context.fetch(FetchDescriptor<DailyCheckIn>()).first)
        #expect([jj.id,mm.id,ww.id,gg.id,cc.id]==ids)
        #expect([jj.owner?.id,mm.owner?.id,ww.owner?.id,gg.owner?.id,cc.owner?.id].allSatisfy { $0==user.id })
        #expect(jj.content==j.content && jj.title=="Full entry" && jj.tags==["kept","fixture"] && jj.date==date)
        #expect(mm.mealName=="Edited meal" && mm.notes==m.notes && mm.photoData==Data([1,3,5,7]))
        #expect(mm.calories==430.5 && mm.protein==24.5 && mm.carbs==50 && mm.fat==12 && mm.date==date)
        #expect(ww.workoutName=="Edited workout" && ww.notes==w.notes && ww.durationMinutes==45 && ww.perceivedExertion==8)
        #expect(ww.exercises[0].id==exerciseID && ww.exercises[0].sets[0].id==setID)
        #expect(ww.exercises[0].sets[0].reps==8 && ww.exercises[0].sets[0].weight==25.5 && ww.exercises[0].sets[0].rpe==7)
        #expect(gg.currentValue==3 && gg.targetValue==8 && gg.unit=="sessions" && gg.category=="personal")
        #expect(gg.adjustmentNotes=="Legacy note kept" && gg.lastAdjustedByCoach==Date(timeIntervalSince1970:20))
        #expect(cc.energyLevel==7 && cc.sorenessLevel==2 && cc.sleepQuality==8 && cc.stressLevel==3 && cc.didTrain)
        #expect(cc.journalNote==c.note && cc.date==date)
    }

    @Test func invalidEditsKeepSavedValuesAndTransactionFailureRollsBack() throws {
        let (directory, container, model)=try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meal=MealLog(mealName:"Kept meal",calories:200,notes:"Kept notes")
        let goal=Goal(name:"Kept goal",currentValue:2,targetValue:4)
        #expect(model.saveRecord(meal));#expect(model.saveRecord(goal))
        var m=MealEditDraft(meal);m.name="Unsaved change";m.calories="12oops"
        #expect(throws:LocalRecordEditError.self) { try m.save(to:meal,using:model) }
        #expect(meal.mealName=="Kept meal" && meal.calories==200 && m.calories=="12oops")
        var g=GoalEditDraft(goal);g.name="Unsaved goal";g.target="0"
        #expect(throws:LocalRecordEditError.self) { try g.save(to:goal,using:model) }
        #expect(goal.name=="Kept goal" && goal.currentValue==2 && goal.targetValue==4)
        #expect(throws:CocoaError.self) {
            try model.commitLocalEdit {
                meal.notes="Must roll back"
                throw CocoaError(.fileWriteUnknown)
            }
        }
        #expect(meal.notes=="Kept notes" && !container.mainContext.hasChanges)
        let fresh=try reopen(directory)
        #expect(try fresh.mainContext.fetch(FetchDescriptor<MealLog>()).first?.notes=="Kept notes")
    }

    @Test func readOnlyAndRetiredSessionsRejectEditingAndIndividualDeletion() throws {
        let (directory, container, model)=try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meal=MealLog(mealName:"Kept",photoData:Data([7,8]))
        let habit=Habit(name:"Kept habit")
        #expect(model.saveRecord(meal));#expect(model.saveRecord(habit))
        let readonlyURL=directory.appendingPathComponent("readonly.sqlite")
        try model.exportDatabase().write(to:readonlyURL)
        let schema=Schema(LuminaApp.modelTypes)
        let readonly=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:readonlyURL,allowsSave:false,cloudKitDatabase:.none)])
        let readonlyModel=LuminaViewModel(modelContext:readonly.mainContext)
        let saved=try #require(readonly.mainContext.fetch(FetchDescriptor<MealLog>()).first)
        var roDraft=MealEditDraft(saved);roDraft.notes="Keep this unsaved draft"
        #expect(throws:LocalRecordEditError.self) { try roDraft.save(to:saved,using:readonlyModel) }
        #expect(throws:LocalRecordEditError.self) { try readonlyModel.deleteLocalRecord(saved) }
        #expect(saved.notes==nil && saved.photoData==Data([7,8]) && roDraft.notes=="Keep this unsaved draft")
        #expect(!readonly.mainContext.hasChanges)
        var oldMealDraft=MealEditDraft(meal);oldMealDraft.name="Stale edit"
        let oldHabitDraft=HabitEditDraft(habit)
        try model.deleteAllLocalRecords()
        #expect(throws:LocalRecordEditError.self) { try oldMealDraft.save(to:meal,using:model) }
        #expect(throws:LocalRecordEditError.self) { try oldHabitDraft.save(to:habit,using:model) }
        #expect(throws:LocalRecordEditError.self) { try model.deleteLocalRecord(meal) }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>())==0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Habit>())==0)
        #expect(!container.mainContext.hasChanges)
    }

    @Test func individualDeletionPreservesOtherRecordsAndIndependentBackup() throws {
        let (directory, container, model)=try makeStore()
        defer { try? FileManager.default.removeItem(at:directory) }
        let removed=MealLog(mealName:"Remove this only",photoData:Data([1,2,3]))
        let kept=MealLog(mealName:"Keep this",notes:"Unrelated notes",photoData:Data([9,8,7]))
        #expect(model.saveRecord(removed));#expect(model.saveRecord(kept))
        #expect(model.saveRecord(JournalEntry(content:"Unrelated full journal")))
        let backupURL=directory.appendingPathComponent("backup.sqlite")
        try model.exportDatabase().write(to:backupURL)
        let removedID=removed.id
        try model.deleteLocalRecord(removed)
        let fresh=try reopen(directory)
        let meals=try fresh.mainContext.fetch(FetchDescriptor<MealLog>())
        #expect(meals.count==1 && meals.first?.id==kept.id)
        #expect(meals.first?.photoData==Data([9,8,7]) && meals.first?.notes=="Unrelated notes")
        #expect(try fresh.mainContext.fetch(FetchDescriptor<JournalEntry>()).first?.content=="Unrelated full journal")
        let schema=Schema(LuminaApp.modelTypes)
        let backup=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:backupURL,cloudKitDatabase:.none)])
        let original=try backup.mainContext.fetch(FetchDescriptor<MealLog>())
        #expect(original.count==2 && original.contains { $0.id==removedID && $0.photoData==Data([1,2,3]) })
        #expect(!container.mainContext.hasChanges)
    }

    @Test func numericDraftsRejectMalformedValuesAndPreserveSetIdentifiers() throws {
        #expect(try LocalRecordDraft.number("12,5",field:"weight",locale:Locale(identifier:"fr_FR"))==12.5)
        #expect(try LocalRecordDraft.number("١٢٫٥",field:"weight",locale:Locale(identifier:"ar_SA"))==12.5)
        #expect(try LocalRecordDraft.number("",field:"weight")==nil)
        for value in ["-1","NaN","inf","12x","1,000","1e999",""] {
            #expect(throws:LocalRecordEditError.self) {
                try LocalRecordDraft.number(value,field:"weight",required:true,locale:Locale(identifier:"en_US"))
            }
        }
        let original=LoggedSet(reps:8,weight:nil,rpe:7)
        var draft=WorkoutSetDraft(original)
        draft.weight="25.5";draft.repetitions="12"
        let saved=try draft.validated()
        #expect(saved.id==original.id && saved.reps==12 && saved.weight==25.5 && saved.rpe==7)
        draft.repetitions="bad"
        #expect(throws:LocalRecordEditError.self) { try draft.validated() }
        #expect(draft.repetitions=="bad")
        draft.repetitions="0"
        #expect(throws:LocalRecordEditError.self) { try draft.validated() }
        draft.repetitions="12";draft.exertion="11"
        #expect(throws:LocalRecordEditError.self) { try draft.validated() }

        // Real draft/save paths intentionally omit a locale argument. The old
        // helper-only Arabic test above did not cover an English phone whose
        // app language or unsaved decimal text is Arabic.
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "ar_SA")] {
            #expect(try LocalRecordDraft.number("١٢٫٥", field: "weight", locale: locale) == 12.5)
            #expect(try LocalRecordDraft.number("12.5", field: "weight", locale: locale) == 12.5)
            for malformed in ["١٬٠٠٠", "1,000", "12٫5.2", "12.5٫2", "12kg", "1 000", "١٢٫٥x"] {
                #expect(throws: LocalRecordEditError.self) {
                    try LocalRecordDraft.number(malformed, field: "weight", required: true, locale: locale)
                }
            }
        }
        #expect(LocalRecordDraft.numberText(0.25, locale: Locale(identifier: "en_US")) == "0.25")
        #expect(LocalRecordDraft.numberText(0.25, locale: Locale(identifier: "ar_SA")) == "0٫25")
        // Use the app's actual numeric policy, separately from the UI locale
        // supplied to date pickers and other native controls.
        #expect(LocalRecordDraft.numberText(12.5, locale: AppLanguage.arabic.numericLocale) == "12٫5")
        #expect(LocalRecordDraft.numberText(12.5, locale: AppLanguage.english.numericLocale) == "12.5")
        #expect(LocalRecordDraft.numberText(0.25) == "0" +
            (LocalizationManager.shared.currentLanguage.numericLocale.decimalSeparator ?? ".") + "25")

        let (directory, container, model) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var goalDraft = GoalEditDraft()
        goalDraft.name = "Fractional goal"; goalDraft.current = "٠٫١٢٥"; goalDraft.target = "٠٫٢٥"
        try goalDraft.save(to: nil, using: model)
        let meal = MealLog(mealName: "Decimal meal")
        #expect(model.saveRecord(meal))
        var mealDraft = MealEditDraft(meal)
        mealDraft.calories = "١٢٫٥"; mealDraft.protein = "٠٫٢٥"
        mealDraft.carbs = "3.5"; mealDraft.fat = "٠٫١٢٥"
        try mealDraft.save(to: meal, using: model)
        let workout = WorkoutLog(workoutName: "Decimal workout", exercises: [
            LoggedExercise(name: "Decimal set", sets: [LoggedSet(reps: 8, weight: nil)])
        ])
        #expect(model.saveRecord(workout))
        var workoutDraft = WorkoutEditDraft(workout)
        workoutDraft.exercises[0].sets[0].weight = "١٢٫٥"
        try workoutDraft.save(to: workout, using: model)
        #expect(!container.mainContext.hasChanges)
        let reopened = try reopen(directory)
        let savedGoal = try #require(reopened.mainContext.fetch(FetchDescriptor<Goal>()).first)
        let savedMeal = try #require(reopened.mainContext.fetch(FetchDescriptor<MealLog>()).first)
        let savedWorkout = try #require(reopened.mainContext.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(savedGoal.currentValue == 0.125 && savedGoal.targetValue == 0.25)
        #expect(savedMeal.calories == 12.5 && savedMeal.protein == 0.25 && savedMeal.carbs == 3.5 && savedMeal.fat == 0.125)
        #expect(savedWorkout.exercises[0].sets[0].weight == 12.5)
        #expect(savedWorkout.exercises[0].sets[0].id == workout.exercises[0].sets[0].id)
    }

    private func makeStore() throws -> (URL,ModelContainer,LuminaViewModel) {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-record-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let container=try reopen(directory)
        return (directory,container,LuminaViewModel(modelContext:container.mainContext))
    }
    private func reopen(_ directory:URL) throws -> ModelContainer {
        let schema=Schema(LuminaApp.modelTypes)
        return try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:directory.appendingPathComponent("records.sqlite"),cloudKitDatabase:.none)])
    }
}
