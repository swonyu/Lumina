import Foundation
import SwiftData
import Testing
@testable import Lumina

@MainActor
struct CoachContextIntegrityTests {
    @Test func editedLargeProteinSurvivesReopenAndOfflineReply() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lumina-coach-number-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(LuminaApp.modelTypes)
        let configuration = ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("fixture.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let model = LuminaViewModel(modelContext: container.mainContext)
        let meal = MealLog(mealName: "Large finite saved value", protein: 20)
        #expect(model.saveRecord(meal))
        var draft = MealEditDraft(meal)
        draft.protein = "1e300"
        try draft.save(to: meal, using: model)

        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let reopenedModel = LuminaViewModel(modelContext: reopened.mainContext)
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<MealLog>()).first)
        #expect(saved.id == meal.id && saved.protein == 1e300)
        let context = reopenedModel.buildCoachContext()
        #expect(context.summary.contains("Total recorded protein: 1e+300 g"))
        // This exact ordinary-message route evaluates context.summary offline.
        let reply = try await SmartGrokCoach().respondToUser(message: "Hello", context: context)
        #expect(!reply.isEmpty)
        #expect(saved.protein == 1e300)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 1)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<CoachMemoryEntry>()) == 0)
    }

    @Test func summaryHandlesOverflowAndInvalidLegacyNumbersWithoutChangingRecords() {
        let first = MealLog(mealName: "First", protein: .greatestFiniteMagnitude)
        let second = MealLog(mealName: "Second", protein: .greatestFiniteMagnitude)
        let overflowing = context(meals: [first, second]).summary
        #expect(overflowing.contains("Protein total unavailable: saved values exceed the numeric range"))
        #expect(first.protein == Double.greatestFiniteMagnitude
            && second.protein == Double.greatestFiniteMagnitude)

        for value in [Double.infinity, Double.nan, -1] {
            let snapshot = HealthSnapshot()
            snapshot.heartRateVariability = value
            let meal = MealLog(mealName: "Legacy value", protein: value)
            let summary = context(health: [snapshot], meals: [meal]).summary
            #expect(summary.contains("HRV: unavailable (invalid saved value)"))
            #expect(summary.contains("Protein total unavailable: an invalid saved value needs review"))
            if value.isNaN {
                #expect(meal.protein?.isNaN == true && snapshot.heartRateVariability?.isNaN == true)
            } else {
                #expect(meal.protein == value && snapshot.heartRateVariability == value)
            }
        }
        #expect([Int.max, Int.max].average == Double(Int.max))
        #expect([Int.min, Int.min].average == Double(Int.min))
        #expect([Int]().average == nil)
        let habit = Habit(name: "Legacy large count")
        habit.currentStreak = Int.max
        let other = Habit(name: "Other large count")
        other.currentStreak = Int.max
        #expect(context(habits: [habit, other]).summary.contains("Active habits in this context: 2"))
        #expect(habit.currentStreak == Int.max && other.currentStreak == Int.max)
    }

    @Test func summaryStatesRecordScopeAndDistinguishesMissingProteinFromZero() {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let checkIns = [4, 8].map {
            DailyCheckIn(date: old, energyLevel: $0, sorenessLevel: 3,
                sleepQuality: 5, stressLevel: 4, mood: .okay)
        }
        let missing = MealLog(mealName: "No measurement")
        let absent = context(checkIns: checkIns, meals: [missing]).summary
        #expect(absent.contains("Saved check-ins in this context: 2; average energy: 6.0/10"))
        #expect(!absent.contains("Last 7-8 days"))
        #expect(absent.contains("0 with recorded protein. Protein not recorded"))
        #expect(!absent.contains("Total recorded protein: 0"))
        let recorded = MealLog(mealName: "Recorded", protein: 24.5)
        let zero = MealLog(mealName: "Recorded zero", protein: 0)
        let partial = context(meals: [missing, recorded, zero]).summary
        #expect(partial.contains("Saved meals in this context: 3; 2 with recorded protein"))
        #expect(partial.contains("Total recorded protein: 24.5 g"))
        #expect(missing.protein == nil && recorded.protein == 24.5 && zero.protein == 0)
    }

    @Test func localizedArgumentsPreserveValuesTypesAndOrder() {
        // Unknown keys intentionally fall back to their own format string.
        // Exercise the real global entry point without changing language
        // preferences, then check the bound production labels below.
        #expect(L("Fixture %d / %@ / %d", 320, "Good", 8) == "Fixture 320 / Good / 8")
        #expect(L("Fixture %@ / %@", "هادئ", "Ready") == "Fixture هادئ / Ready")
        #expect(LocalizationManager.shared.localized("Fixture %d / %@", 75, "Protein")
            == "Fixture 75 / Protein")
        let english = LocalizationManager.shared.currentLanguage == .english
        #expect(L("meal.calories_label", 320) == (english ? "Calories: 320" : "سعرات: 320"))
        #expect(L("meal.protein_label", 25) == (english ? "Protein: 25g" : "بروتين: 25جم"))
        #expect(L("workout.rpe_label", 8) == "RPE: 8")
        #expect(L("journal.mood_prefix", "Good") == (english ? "Mood: Good" : "المزاج: Good"))
        #expect(L("adaptive.quick_analysis")
            == (english ? "Saved record observations" : "ملاحظات السجلات المحفوظة"))
    }

    @Test func localizedTextWithoutArgumentsRetainsLiteralPercentSigns() {
        #expect(L("Review 100% of saved records") == "Review 100% of saved records")
        #expect(LocalizationManager.shared.localized("Keep 20% for later") == "Keep 20% for later")
    }

    private func context(health: [HealthSnapshot] = [], checkIns: [DailyCheckIn] = [],
                         meals: [MealLog] = [], habits: [Habit] = []) -> CoachContext {
        CoachContext(profile: nil, recentHealth: health, recentCheckIns: checkIns,
            recentWorkouts: [], recentMeals: meals, activeHabits: habits,
            recentInsights: [], currentStreak: 0)
    }
}
