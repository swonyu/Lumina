import Foundation
import SwiftData
import Observation
import HealthKit
import UserNotifications
import ActivityKit
import WidgetKit

@MainActor
@Observable
final class LuminaViewModel {
    var currentUser: UserProfile?
    var recentHealthSnapshots: [HealthSnapshot] = []
    var isLoadingHealthData = false
    var errorMessage: String?

    // Round 6: Persisted coach memory so the AI actually gets smarter over time
    var persistedCoachMemory: [CoachMemoryEntry] = []

    let modelContext: ModelContext   // Exposed for direct goal creation from views (Round 13)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bootstrapAfterLaunch() async {
        loadCurrentUser()

        if currentUser == nil {
            createDemoProfile()
        }

        await fetchRecentHealthData()
        loadPersistedCoachMemory()
        loadGoals()
    }

    func loadCurrentUser() {
        let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let user = try? modelContext.fetch(descriptor).first {
            currentUser = user
        }
    }
    
    private func createDemoProfile() {
        let demo = UserProfile(
            name: "Alex",
            age: 28,
            gender: .male,
            heightCm: 178,
            currentWeightKg: 82,
            goalWeightKg: 74,
            experienceLevel: .intermediate,
            primaryGoal: .buildMuscle,
            workoutDaysPerWeek: 5,
            equipmentAccess: .fullGym,
            dietaryPreferences: [.highProtein]
        )
        modelContext.insert(demo)
        try? modelContext.save()
        currentUser = demo
        
        // Seed some demo activity so the app doesn't feel empty
        seedDemoData()
    }
    
    private func seedDemoData() {
        let now = Date()
        
        // Check-ins with spread dates
        let check1 = DailyCheckIn(date: now.addingTimeInterval(-86400*1), energyLevel: 7, sorenessLevel: 3, sleepQuality: 8, stressLevel: 4, mood: .good, didTrain: true)
        let check2 = DailyCheckIn(date: now.addingTimeInterval(-86400*2), energyLevel: 6, sorenessLevel: 5, sleepQuality: 6, stressLevel: 5, mood: .okay, didTrain: true)
        modelContext.insert(check1)
        modelContext.insert(check2)
        
        // Meals
        modelContext.insert(MealLog(date: now.addingTimeInterval(-3600*3), mealName: "Chicken rice bowl", calories: 620, protein: 48))
        modelContext.insert(MealLog(date: now.addingTimeInterval(-3600*8), mealName: "Greek yogurt + berries", calories: 280, protein: 22))
        
        // Workout
        modelContext.insert(WorkoutLog(date: now.addingTimeInterval(-86400), workoutName: "Push + Core", exercises: [], perceivedExertion: 7, notes: "Felt strong on bench"))
        
        // Some HealthSnapshots so coach context has data
        let snap1 = HealthSnapshot(date: now.addingTimeInterval(-86400*1))
        snap1.sleepHours = 7.5
        snap1.heartRateVariability = 68
        snap1.activeEnergyBurned = 720
        modelContext.insert(snap1)
        
        let snap2 = HealthSnapshot(date: now.addingTimeInterval(-86400*2))
        snap2.sleepHours = 6.2
        snap2.heartRateVariability = 52
        snap2.activeEnergyBurned = 540
        modelContext.insert(snap2)
        
        try? modelContext.save()
        
        // Populate immediately (sync) so Coach tab has context right away
        var descriptor = FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 14
        recentHealthSnapshots = (try? modelContext.fetch(descriptor)) ?? []
    }

    func createOrUpdateProfile(_ profile: UserProfile) {
        if currentUser == nil {
            modelContext.insert(profile)
        }
        currentUser = profile
        try? modelContext.save()
    }

    private let healthStore = HKHealthStore()

    func seedStartupServices() async {
        await requestNotificationPermission()
        await scheduleProactiveCoachNotifications()
        startCoachFocusLiveActivity()
    }

    func requestHealthKitAccess() async {
        isLoadingHealthData = true
        errorMessage = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit not available on this device."
            isLoadingHealthData = false
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            
            // Fetch real recent data
            await fetchRealHealthDataFromHealthKit()
            
        } catch {
            errorMessage = "HealthKit authorization failed: \(error.localizedDescription)"
            // Fall back to demo data
            await seedDemoHealthDataIfNeeded()
        }
        
        isLoadingHealthData = false
    }

    private func fetchRealHealthDataFromHealthKit() async {
        let now = Date()
        var snapshots: [HealthSnapshot] = []

        // Fetch last 7 days of key metrics
        for dayOffset in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: -dayOffset, to: now)!
            let snapshot = HealthSnapshot(date: day)

            // HRV
            if let hrv = try? await fetchLatestHRV(before: day) {
                snapshot.heartRateVariability = hrv
            }

            // Active Energy
            if let energy = try? await fetchActiveEnergy(for: day) {
                snapshot.activeEnergyBurned = energy
            }

            // Sleep (previous night)
            if let sleep = try? await fetchSleepHours(for: day) {
                snapshot.sleepHours = sleep
            }

            modelContext.insert(snapshot)
            snapshots.append(snapshot)
        }

        try? modelContext.save()
        recentHealthSnapshots = snapshots.sorted { $0.date > $1.date }
    }

    private func fetchLatestHRV(before date: Date) async throws -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: date)!), end: date)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: sample.quantity.doubleValue(for: .secondUnit(with: .milli)))
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveEnergy(for date: Date) async throws -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error { continuation.resume(throwing: error); return }
                let value = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: value > 0 ? value : nil)
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepHours(for date: Date) async throws -> Double? {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startOfDay = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: date)!)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: date)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let samples = samples as? [HKCategorySample] else { continuation.resume(returning: nil); return }
                
                let asleep = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                                             $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                                             $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                                             $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let hours = total / 3600
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            healthStore.execute(query)
        }
    }

    private func seedDemoHealthDataIfNeeded() async {
        if recentHealthSnapshots.isEmpty {
            let now = Date()
            let s1 = HealthSnapshot(date: now.addingTimeInterval(-86400))
            s1.sleepHours = 7.2; s1.heartRateVariability = 61; s1.activeEnergyBurned = 680; s1.energyLevel = 7
            modelContext.insert(s1)
            
            let s2 = HealthSnapshot(date: now.addingTimeInterval(-86400*2))
            s2.sleepHours = 6.8; s2.heartRateVariability = 55; s2.activeEnergyBurned = 510; s2.energyLevel = 6
            modelContext.insert(s2)
            
            try? modelContext.save()
            recentHealthSnapshots = [s2, s1]
        }
    }

    func fetchRecentHealthData() async {
        isLoadingHealthData = true
        var descriptor = FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 14
        recentHealthSnapshots = (try? modelContext.fetch(descriptor)) ?? []
        isLoadingHealthData = false

        syncWidgetData()   // Round 106: rings may have changed
    }

    func getRecentHealthContextForAI() -> [HealthSnapshot] {
        Array(recentHealthSnapshots.prefix(7))
    }

    /// Rich context for the AI coach (health + recent behavior + habits + memory signals for much smarter decisions)
    func buildCoachContext() -> CoachContext {
        // Use cached where possible for perf
        let checkInDesc = FetchDescriptor<DailyCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let recentCheckIns = (try? modelContext.fetch(checkInDesc))?.prefix(8).map { $0 } ?? []

        let recentWorkoutsFetched = recentWorkouts // uses VM cache

        let mealDesc = FetchDescriptor<MealLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let recentMeals = (try? modelContext.fetch(mealDesc))?.prefix(6).map { $0 } ?? []

        // NEW: Use cached active habits (perf + the enriched context that makes the coach dramatically smarter)
        let activeHabits = activeHabits // VM cached property (Round 40)

        // NEW: Pull recent high-value memory insights (photo analyses, meal feedback, form checks, weekly accepts) so coach references them
        let insightMemories = persistedCoachMemory.filter { $0.type == .insight }.prefix(5).map { $0.content }

        return CoachContext(
            profile: currentUser,
            recentHealth: recentHealthSnapshots,
            recentCheckIns: Array(recentCheckIns),
            recentWorkouts: recentWorkoutsFetched,
            recentMeals: Array(recentMeals),
            activeHabits: Array(activeHabits),
            recentInsights: Array(insightMemories),
            currentStreak: max(recentCheckIns.count, recentWorkoutsFetched.count)
        )
    }
    
    // Cached for performance (avoids SwiftData fetch on every view body eval)
    private var _cachedTodaysFocusWorkout: String?
    var todaysFocusWorkout: String {
        if let cached = _cachedTodaysFocusWorkout { return cached }
        var descriptor = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        let name = (try? modelContext.fetch(descriptor).first?.workoutName) ?? "Push + Core"
        _cachedTodaysFocusWorkout = name
        return name
    }
    
    func invalidateFocusCache() {
        _cachedTodaysFocusWorkout = nil
    }
    
    // Cached recent workouts for Live Activity + coach (perf + fixes broken reference)
    private var _cachedRecentWorkouts: [WorkoutLog]?
    var recentWorkouts: [WorkoutLog] {
        if let cached = _cachedRecentWorkouts { return cached }
        let desc = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let fetched = (try? modelContext.fetch(desc))?.prefix(5).map { $0 } ?? []
        _cachedRecentWorkouts = Array(fetched)
        return _cachedRecentWorkouts!
    }
    
    func invalidateWorkoutsCache() {
        _cachedRecentWorkouts = nil
        invalidateFocusCache()
    }
    
    // NEW Round 40: Cached active habits (perf for the now-rich buildCoachContext + proactive logic)
    private var _cachedActiveHabits: [Habit]?
    var activeHabits: [Habit] {
        if let cached = _cachedActiveHabits { return cached }
        let desc = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = (try? modelContext.fetch(desc))?.filter { $0.isActive }.prefix(6).map { $0 } ?? []
        _cachedActiveHabits = Array(fetched)
        return _cachedActiveHabits!
    }
    
    func invalidateHabitsCache() {
        _cachedActiveHabits = nil
    }
    
    var todaysFocusDuration: String {
        "45-50 min"  // Could be made smarter with more data
    }
    
    // Dynamic rings for Home (based on seeded + recent data)
    var recoveryValue: Int {
        guard !recentHealthSnapshots.isEmpty else { return 73 }
        let sleepVals = recentHealthSnapshots.compactMap { $0.sleepHours }
        let avgSleep = sleepVals.isEmpty ? 7.0 : sleepVals.reduce(0, +) / Double(sleepVals.count)
        let energyVals = recentHealthSnapshots.compactMap { $0.energyLevel }
        let avgEnergy = energyVals.isEmpty ? 5.0 : Double(energyVals.reduce(0, +)) / Double(energyVals.count)
        let base = 60 + (avgSleep - 6) * 8 + (avgEnergy - 5) * 2
        return min(max(Int(base), 55), 92)
    }
    
    var nutritionValue: Int {
        // Simple demo based on recent check-ins + profile goal
        guard let user = currentUser else { return 68 }
        let base = user.primaryGoal == .buildMuscle ? 72 : 65
        let energyVals = recentHealthSnapshots.compactMap { $0.energyLevel }
        let recentAvg = energyVals.isEmpty ? 5.0 : Double(energyVals.reduce(0, +)) / Double(energyVals.count)
        return min(max(Int(Double(base) + (recentAvg - 5) * 3), 50), 90)
    }
    
    var readinessValue: Int {
        guard !recentHealthSnapshots.isEmpty else { return 84 }
        let hrvVals = recentHealthSnapshots.compactMap { $0.heartRateVariability }
        let avgHRV = hrvVals.isEmpty ? 50.0 : hrvVals.reduce(0, +) / Double(hrvVals.count)
        return min(max(Int(60 + (avgHRV - 50) * 0.6), 65), 95)
    }
    
    // MARK: - Proactive AI Coach Insight (Round 3)
    var currentCoachInsight: String = "Your recent HRV trend looks solid. Great window to push a bit harder if energy stays good."
    var isGeneratingInsight: Bool = false
    private var lastInsightRefresh: Date?

    // Persisted last AI outputs so they survive navigation (Round 3)
    var lastGeneratedAIPlan: String?
    var lastWeeklyReflection: String?

    // Round 7: Proactive actionable suggestions from the coach shown directly on Home
    var homeCoachSuggestions: [HomeCoachSuggestion] = []
    
    // Round 12/13: Real persisted goals + AI adjustments
    var goals: [Goal] = []
    var recentGoalAdjustments: [String] = []
    
    // Round 16: High-quality LLM-generated memory summary (when available)
    var smartMemorySummary: String = ""
    
    // Round 23: Proactive, AI-generated daily insight for the Home screen (makes the coach feel more autonomous)
    var proactiveHomeInsight: String = ""
    
    struct HomeCoachSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let actionType: ActionType
        
        enum ActionType {
            case logCheckIn
            case logQuickWorkout
            case openCoachChat
            case adjustGoal          // Round 27: richer autonomous action
            case reviewPlan          // Round 27: coach surfaces plan adjustment opportunity
        }
    }
    
    // Round 27: High-signal autonomous recommendation surfaced on Home (pattern-driven goal/plan work)
    var proactiveCoachRecommendation: String = ""
    var proactiveRecommendationAction: HomeCoachSuggestion.ActionType = .openCoachChat
    var showingProactiveRecommendation: Bool = false
    
    // Round 41: Dynamic category for the "Coach noticed" card so it feels more intelligent (habits, photos, recovery, etc.)
    var proactiveRecommendationCategory: String = "pattern"
    
    // Round 62: Lightweight signal so surfaces (Home, Progress Photos) can react to coach wanting a photo for habit outcome tracking
    var coachWantsProgressPhotoForHabit: Bool = false
    
    // Round 68: Temporary reflection to surface on Home after a coach-requested photo analysis completes
    var coachPhotoReflection: String? = nil
    
    // Round 70: Navigation request from coach surfaces (e.g. reflection card)
    var requestedTab: Int? = nil
    
    // Round 71: Lightweight signal that the next photo analysis is for a coach-requested habit outcome (so we can surface real analysis text)
    var pendingCoachPhotoAnalysis: Bool = false
    
    var dynamicBriefingCapsuleTitle: String {
        briefingCapsuleTitle
    }
    
    // Round 95: Cheap computed for the Daily Briefing habit capsule "streak" title variant
    var isStreakBasedBriefingCapsule: Bool {
        proactiveCoachRecommendation.lowercased().contains("streak")
    }
    
    // Round 96: Full dynamic computed for the Daily Briefing habit capsule title (centralizes all variants using capsule state)
    var briefingCapsuleTitle: String {
        if isPositiveWinForBriefingCapsule {
            return "Capture habit win"
        } else if isStreakBasedBriefingCapsule {
            return "Log habit streak"
        } else {
            return "Log habit win"
        }
    }
    
    // Round 80 perf + polish: Pre-computed card header label and "why" transparency text for the autonomous "Coach noticed" recommendation card.
    // Eliminates repeated .lowercased() + conditional string work on every ModernHomeView body evaluation.
    var proactiveCardHeaderLabel: String {
        if proactiveRecommendationCategory == "habit" {
            let lower = proactiveCoachRecommendation.lowercased()
            if lower.contains("win") || lower.contains("delivering") || lower.contains("early") {
                return "Coach noticed a winning habit"
            }
            return "Coach noticed habit pattern"
        } else if proactiveRecommendationCategory == "photo" {
            return "Coach noticed progress"
        } else if proactiveRecommendationCategory == "recovery" {
            return "Coach noticed recovery issue"
        } else {
            return "Coach noticed a pattern"
        }
    }
    
    var proactiveCardWhyText: String {
        if proactiveRecommendationCategory == "habit" {
            let lower = proactiveCoachRecommendation.lowercased()
            if lower.contains("win") || lower.contains("delivering") || lower.contains("early") {
                return "Based on early positive results from a coach-suggested habit"
            }
            return "Based on your current habit streaks & adherence"
        } else if proactiveRecommendationCategory == "photo" {
            return "Based on visible progress in your photos + training data"
        } else if proactiveRecommendationCategory == "recovery" {
            return "Based on recent energy & recovery patterns"
        } else {
            return "Based on your recent patterns in memory"
        }
    }
    
    // Round 86 perf + hygiene: Cheap computed flag for limited-impact coach habit memories (reduces repeated .contains across views and chat logic)
    var hasLimitedCoachHabitImpact: Bool {
        persistedCoachMemory.contains { $0.type == .pattern && ($0.content.lowercased().contains("limited visible impact") || $0.content.lowercased().contains("limited impact")) }
    }
    
    // Round 87: Lightweight summary string of limited-impact coach habits (for easy injection into prompts and nudges)
    var limitedImpactCoachHabitsSummary: String {
        let limited = persistedCoachMemory.filter { $0.type == .pattern && ($0.content.lowercased().contains("limited visible impact") || $0.content.lowercased().contains("limited impact")) }
        guard !limited.isEmpty else { return "" }
        return limited.prefix(3).map { $0.content.prefix(120) }.joined(separator: " | ")
    }
    
    // Round 89 perf + hygiene: Cheap computed for the Home autonomous rec card "winning habit" state (eliminates repeated .lowercased() in ModernHomeView)
    var isWinningHabitRec: Bool {
        proactiveRecommendationCategory == "habit" &&
        (proactiveCoachRecommendation.lowercased().contains("win") ||
         proactiveCoachRecommendation.lowercased().contains("delivering") ||
         proactiveCoachRecommendation.lowercased().contains("early"))
    }
    
    // Round 90: Cheap computed for the Daily Briefing habit capsule background treatment (positive win vs measurement)
    var isPositiveCoachHabitWinCapsule: Bool {
        proactiveRecommendationCategory == "habit" && isWinningHabitRec
    }
    
    // Round 91: Cheap computed for the Daily Briefing habit capsule camera icon (positive win case)
    var shouldShowCameraInBriefingCapsule: Bool {
        isPositiveCoachHabitWinCapsule
    }
    
    // Round 93: Unified computed for the Daily Briefing habit capsule "positive win" state (drives visual + camera + action logic)
    var isPositiveWinForBriefingCapsule: Bool {
        isPositiveCoachHabitWinCapsule
    }
    
    /// Convenience for views to create a suggestion for the autonomous recommendation flow
    func makeProactiveSuggestion() -> HomeCoachSuggestion {
        HomeCoachSuggestion(title: proactiveCoachRecommendation, actionType: proactiveRecommendationAction)
    }
    
    // Round 97: Cheap computed for the Home autonomous rec card action button text (eliminates ternary in ModernHomeView)
    var proactiveRecActionButtonText: String {
        proactiveRecommendationAction == .adjustGoal ? "Apply adjustment" : "Review & update plan"
    }
    
    // Round 100: Cheap computed for the Home autonomous rec card SF Symbol icon (eliminates inline category ternary + repeated string work in ModernHomeView body on every render)
    var proactiveRecIconName: String {
        if proactiveRecommendationCategory == "habit" {
            return "list.bullet"
        } else if proactiveRecommendationCategory == "photo" {
            return "photo"
        } else if proactiveRecommendationCategory == "recovery" {
            return "bed.double"
        } else {
            return "lightbulb.max"
        }
    }
    
    // Round 100: Cheap computed for the post-action success follow-up button logic (eliminates 3x repeated .lowercased() + contains checks inside the success card view body)
    var followUpSuccessPrefersPhotoCapture: Bool {
        let msg = followUpSuccessMessage.lowercased()
        return msg.contains("habit added") || msg.contains("first win") || msg.contains("winning")
    }
    
    // Round 101: Cheap computed for the *current* coachPhotoReflection text (used for immediate UI nudges after analysis). Centralizes the limited-impact phrasing check across Goals/Recovery/Live Activity.
    var currentCoachPhotoReflectionShowsLimitedImpact: Bool {
        guard let r = coachPhotoReflection, !r.isEmpty else { return false }
        let lower = r.lowercased()
        return lower.contains("limited visible impact") || lower.contains("limited impact") || lower.contains("limited") || lower.contains("no clear") || lower.contains("no visible")
    }
    
    // Round 28: LLM-powered Daily Briefing (replaces brittle heuristic)
    var coachDailyBriefing: String = ""
    var isGeneratingBriefing: Bool = false
    private var lastBriefingRefresh: Date?
    
    // Round 29: Multi-turn autonomy — after user acts on a goal/plan recommendation, surface one smart contextual follow-up
    var postActionCoachFollowUp: String = ""
    var showingPostActionFollowUp: Bool = false
    var postActionFollowUpAction: HomeCoachSuggestion.ActionType? = nil   // Round 30: makes the follow-up actually do something useful
    var isExecutingFollowUp: Bool = false   // Round 30 polish: loading state while we generate a plan etc.
    var followUpSuccessMessage: String = ""   // Round 31: brief positive feedback after a follow-up action completes

    // Proactive Notifications
    var notificationsAuthorized = false
    
    // Voice Notes integration
    var pendingVoiceMessage: String? = nil
    
    // Coach Habit Intelligence (Round 37)
    var coachHabitSuggestions: [String] = []
    
    // Round 48: Lightweight published signal for local success feedback in HabitTracker coach sheet
    var justAddedCoachHabit: String? = nil

    /// Generates (or refreshes) a smart, personalized daily insight from Grok when possible.
    /// Falls back to excellent local logic. Call this on home appear or pull-to-refresh.
    func refreshCoachInsight(force: Bool = false) async {
        // Avoid hammering the API on every re-render
        if !force, let last = lastInsightRefresh, Date().timeIntervalSince(last) < 45 {
            return
        }

        isGeneratingInsight = true

        let context = buildCoachContext()
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""

        if !apiKey.isEmpty {
            let service = GrokService(apiKey: apiKey)
            let longTerm = longTermCoachContext
            let prompt = """
            You are Lumina's daily insight engine. Give the user ONE short, specific, actionable insight for TODAY based on their recent data and long-term patterns.
            Keep it to 1-2 sentences max. Be warm, direct, and data-aware. Do not give generic motivation.
            
            Recent context:
            \(context.summary)
            
            Long-term memory you have about this user:
            \(longTerm.isEmpty ? "No long-term memory yet." : longTerm)
            """

            do {
                // We reuse the emotional support path with a crafted system prompt for a "daily insight" style reply
                let insight = try await service.getSmartEmotionalSupport(
                    userMessage: "Give me today's personalized insight.",
                    context: context
                )
                await MainActor.run {
                    self.currentCoachInsight = insight
                    self.lastInsightRefresh = Date()
                }
                
                // Round 9: Try LLM-powered suggestions when key is available (much smarter)
                await generateHomeCoachSuggestionsWithAI(from: context)
                
            } catch {
                // Fall through to local fallback
                await MainActor.run {
                    self.currentCoachInsight = self.generateLocalInsight(context: context)
                }
                await generateHomeCoachSuggestionsWithAI(from: context)
            }
        } else {
            await MainActor.run {
                self.currentCoachInsight = self.generateLocalInsight(context: context)
            }
            await generateHomeCoachSuggestionsWithAI(from: context)
        }

        isGeneratingInsight = false
        
        // Round 16: Also generate high-quality memory summary in background
        Task {
            let summary = await generateMemorySummaryWithAI()
            await MainActor.run {
                self.smartMemorySummary = summary
            }
        }
        
        // Round 23: Generate a short, proactive daily insight from the coach using the smart memory
        Task {
            await generateProactiveHomeInsight()
        }
        
        // Round 27: Also keep the autonomous pattern recommendation fresh
        Task {
            await generateProactiveCoachRecommendation()
        }
        
        // Round 30/31 + 39: Stronger state hygiene — clear all multi-turn coach UI state on full Home refresh to prevent leakage
        isExecutingFollowUp = false
        followUpSuccessMessage = ""
        postActionCoachFollowUp = ""
        showingPostActionFollowUp = false
        postActionFollowUpAction = nil
        // Do NOT clear the main proactive recommendation here (user may still want to act on it)
    }
    
    /// Round 23: Generate a short, autonomous daily insight for the Home screen using the coach's memory.
    func generateProactiveHomeInsight() async {
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else { return }
        
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        guard !memory.isEmpty else { return }
        
        let service = GrokService(apiKey: apiKey)
        let ctx = buildCoachContext()
        
        let prompt = """
        You are Lumina, an insightful AI coach. Based on the user's long-term patterns and recent data below (including habits and photo/meal insights), write ONE short, warm, specific observation or gentle suggestion for today (max 22 words).
        Make it feel personal and like you're thinking ahead for them. When a very new coach-suggested habit was just added with no wins yet, gently nudge toward logging the first completion or photo.
        
        Recent data: \(ctx.summary)
        Long-term patterns: \(memory.prefix(600))
        """
        
        do {
            let insight = try await service.getSmartEmotionalSupport(
                userMessage: "Give me one thoughtful daily observation.",
                context: ctx,
                longTermMemory: memory
            )
            
            let cleaned = insight.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && cleaned.count < 140 {
                await MainActor.run {
                    self.proactiveHomeInsight = cleaned
                }
            }
        } catch {
            // Silent fallback
        }
    }

    /// Round 28: Generate a truly intelligent, personalized Daily Briefing using the coach's best memory summary.
    /// This replaces the previous brittle keyword-based heuristic and makes the coach feel much wiser every launch.
    func generateCoachDailyBriefing() async {
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        
        // Light rate limit + avoid regenerating identical content constantly
        if let last = lastBriefingRefresh, Date().timeIntervalSince(last) < 60, !coachDailyBriefing.isEmpty {
            return
        }
        
        isGeneratingBriefing = true
        
        if !apiKey.isEmpty && !memory.isEmpty {
            let service = GrokService(apiKey: apiKey)
            let ctx = buildCoachContext()
            
            let prompt = """
            You are Lumina, a wise and caring AI coach. The user has just opened the app.
            
            Using ONLY the long-term patterns and recent data below, write ONE short, specific, warm daily briefing (1-2 sentences, max 28 words).
            Make it feel like you have been thoughtfully considering their unique situation overnight.
            Reference real patterns (energy, consistency, recovery, goals, recent coach-suggested habit additions and their early outcomes — both wins showing in energy/photos and habits with activity but no measured impact yet). 
            If the long-term memory contains high-quality "limited visible impact" entries from coach-requested photo analyses (with cross-signal data), honestly but kindly call out the specific habit and suggest a small concrete next step (review, adjust, or fresh photo/check-in).
            If the user recently captured a photo specifically at your request for a habit, gently acknowledge that action and reference any key findings from the photo analysis (e.g. visible progress on the habit or areas still needing measurement). When analysis showed limited/no clear impact, be honest and kind about it and suggest a concrete small next step (photo, check-in, or adjustment).
            Be direct and kind. Name specific coach habits when relevant. No generic motivation.
            
            Long-term patterns (your memory of this person):
            \(memory.prefix(700))
            
            Explicit limited-impact summary on your own prior coach-suggested habits (from photo analyses + cross-signal HealthKit/meals/streaks data — use this as primary signal for honesty):
            \(limitedImpactCoachHabitsSummary.isEmpty ? "None currently flagged." : limitedImpactCoachHabitsSummary)
            
            Recent context:
            \(ctx.summary)
            """
            
            do {
                let briefing = try await service.getSmartEmotionalSupport(
                    userMessage: "Write my personalized daily briefing for today.",
                    context: ctx,
                    longTermMemory: memory
                )
                
                let cleaned = briefing.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count < 220 {
                    await MainActor.run {
                        self.coachDailyBriefing = cleaned
                        self.lastBriefingRefresh = Date()
                        self.syncWidgetData()   // Round 106: push fresh briefing to widget
                    }
                    isGeneratingBriefing = false
                    return
                }
            } catch {
                // fall through to local
            }
        }
        
        // High-quality local fallback (still better than the old keyword soup)
        let local = generateLocalBriefing(memory: memory)
        await MainActor.run {
            self.coachDailyBriefing = local
            self.lastBriefingRefresh = Date()
            self.syncWidgetData()   // Round 106: push fresh local briefing to widget
        }
        isGeneratingBriefing = false
    }
    
    private func generateLocalBriefing(memory: String) -> String {
        let s = memory.lowercased()
        if s.contains("energy") || s.contains("tired") || s.contains("recovery") {
            return "Your recent energy and recovery patterns suggest keeping today's movement intentional and protecting sleep. Small, high-quality effort will serve you best."
        } else if s.contains("consistent") && !s.contains("inconsistent") {
            return "Consistency has been your superpower lately. One focused session today will compound that momentum meaningfully this week."
        } else if !recentGoalAdjustments.isEmpty || s.contains("goal") {
            return "You've been doing good thinking with me on your goals. Let's keep the focus on the highest-leverage action that moves the needle today."
        } else if s.contains("inconsistent") || s.contains("skipped") {
            return "Life gets in the way sometimes. A kind, small action today resets the rhythm better than aiming for perfection."
        } else if (s.contains("coach habit") || s.contains("added habit")) && (s.contains("win") || s.contains("showing") || s.contains("energy") || s.contains("photo")) {
            // Round 60: Positive outcome for coach habits
            return "One of your coach-suggested habits is already delivering early wins. Logging today's completion and capturing it with a photo will lock in the momentum."
        } else if s.contains("added habit") || s.contains("new habit") || (s.contains("coach habit") && s.contains("streak")) {
            // Round 58/60: Honest impact language
            return "You have active coach-suggested habits with some early activity. A quick win log or progress photo today will help measure whether they're moving the needle."
        } else if s.contains("coach-requested") && s.contains("photo") {
            // Round 66: Acknowledge recent coach-driven photo action
            return "You recently captured a progress photo at my request for one of your habits. That data will help us see real results."
        } else if hasLimitedCoachHabitImpact || currentCoachPhotoReflectionShowsLimitedImpact {
            // Round 74 + 101 + 102 + 103 + 104: Use centralized limited-impact detection + actual summary for much smarter offline Daily Briefing
            let detail = !limitedImpactCoachHabitsSummary.isEmpty ? " \(limitedImpactCoachHabitsSummary)" : ""
            return "Recent coach photo analysis shows limited visible impact on a habit so far.\(detail) Let's review and adjust or capture more data."
        } else if s.contains("progress photo analysis") && s.contains("coach") {
            // Round 74 + 80: Reference recent coach photo analysis insights in local briefing with outcome-aware tone
            return "Your recent coach photo analysis has fresh insights on a habit — worth reviewing the evidence today."
        }
        return "Your history shows you do best when you start the day with one clear, high-value intention. What will yours be?"
    }
    
    /// Round 29: After the user completes an autonomous goal or plan action, generate one smart, contextual "what should we do next?" follow-up.
    /// This creates true multi-turn agentic behavior.
    private var lastPostActionFollowUpGen: Date?
    
    func generatePostActionFollowUp(after actionType: HomeCoachSuggestion.ActionType, actionTitle: String) async {
        // Round 30 perf: guard against rapid successive autonomous actions firing multiple follow-up generations
        if let last = lastPostActionFollowUpGen, Date().timeIntervalSince(last) < 20 {
            return
        }
        lastPostActionFollowUpGen = Date()
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        let ctx = buildCoachContext()
        
        if !apiKey.isEmpty {
            let service = GrokService(apiKey: apiKey)
            
            let prompt = """
            The user just completed this coach-recommended action on their Home screen: "\(actionTitle)" (type: \(actionType)).
            
            Based on their long-term memory and recent data, suggest ONE very short, natural, intelligent next step they should consider right now (max 18 words).
            Make it feel like a wise coach continuing the conversation naturally.
            Prefer suggesting a logical follow-on action the app supports (plan generation, another small log, or deeper chat).
            
            When the coach's own prior suggestions (especially habits) show "limited visible impact" in photo analyses or cross-signal data, the highest-leverage next step is often an honest review/adjust or fresh measurement rather than pushing forward blindly.
            
            Memory context:
            \(memory.prefix(500))
            
            Explicit limited-impact summary on your own prior coach-suggested habits (primary honesty signal):
            \(limitedImpactCoachHabitsSummary.isEmpty ? "None currently flagged." : limitedImpactCoachHabitsSummary)
            """
            
            if let followUp = try? await service.getSmartEmotionalSupport(
                userMessage: "What is the single best next step after this action?",
                context: ctx,
                longTermMemory: memory
            ) {
                let cleaned = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && cleaned.count < 140 {
                    await MainActor.run {
                        self.postActionCoachFollowUp = cleaned
                        self.showingPostActionFollowUp = true
                        // Round 30: Choose the most logical actionable follow-up
                        self.postActionFollowUpAction = actionType == .adjustGoal ? .reviewPlan : .logQuickWorkout
                    }
                    return
                }
            }
        }
        
        // Round 34 + 105: Stronger memory-aware local fallback (consistent with direct chaining + limited-impact honesty)
        let isAdjust = actionType == .adjustGoal
        let mem = !smartMemorySummary.isEmpty ? smartMemorySummary.lowercased() : memorySummary.lowercased()
        let local: String
        let nextAction: HomeCoachSuggestion.ActionType
        
        // Round 105: Prioritize honest review when the coach's own habit suggestions are showing limited ROI (uses centralized computeds + rich summary)
        if hasLimitedCoachHabitImpact || currentCoachPhotoReflectionShowsLimitedImpact {
            let detail = !limitedImpactCoachHabitsSummary.isEmpty ? " — \(limitedImpactCoachHabitsSummary.prefix(70))" : ""
            local = "Honest note: a coach-suggested habit\(detail) isn't showing clear results yet. Review or adjust it?"
            nextAction = .adjustGoal
        } else if isAdjust && (mem.contains("goal") || mem.contains("adjust")) {
            local = "Good change. Want to review another goal target next?"
            nextAction = .adjustGoal
        } else if isAdjust {
            local = "Good change. Want me to generate a plan that matches your updated goal?"
            nextAction = .reviewPlan
        } else if mem.contains("goal") || mem.contains("adjust") {
            local = "Solid log. Ready to adjust a goal to match this momentum?"
            nextAction = .adjustGoal
        } else if actionTitle.lowercased().contains("habit") || mem.contains("new habit") || mem.contains("added habit") {
            local = "Excellent. Log your first completion on that new habit + snap a quick progress photo — it only takes a moment."
            nextAction = .logCheckIn
        } else if mem.contains("habit") {
            local = "Solid move. Ready to log your first win on the new habit?"
            nextAction = .logCheckIn
        } else {
            local = "Plan refreshed. Would you like to log a session aligned with it today?"
            nextAction = .logQuickWorkout
        }
        
        await MainActor.run {
            self.followUpSuccessMessage = ""
            self.postActionCoachFollowUp = local
            self.showingPostActionFollowUp = true
            self.postActionFollowUpAction = nextAction
        }
    }
    
    /// Round 30: Execute the follow-up suggestion when user taps "Let's do it".
    /// This is what makes the multi-turn coach feel truly agentic and useful.
    @MainActor
    func executePostActionFollowUp() {
        guard let action = postActionFollowUpAction else {
            showingPostActionFollowUp = false
            postActionCoachFollowUp = ""
            return
        }
        
        // Round 31 perf: simple re-entrancy guard for expensive follow-up actions
        if isExecutingFollowUp { return }
        
        isExecutingFollowUp = true
        
        // Clear UI state first
        showingPostActionFollowUp = false
        let previousText = postActionCoachFollowUp
        postActionCoachFollowUp = ""
        postActionFollowUpAction = nil
        
        switch action {
        case .reviewPlan:
            // Actually generate a fresh plan using the latest memory/context
            saveCoachMemoryEntry(type: .pattern, content: "User acted on coach follow-up suggestion: \(previousText)")
            
            let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
            if !apiKey.isEmpty, let profile = currentUser {
                Task {
                    let service = GrokService(apiKey: apiKey)
                    if let plan = try? await service.generateSmartWorkoutPlan(profile: profile, context: buildCoachContext()) {
                        await MainActor.run {
                            self.lastGeneratedAIPlan = plan
                            self.saveCoachMemoryEntry(type: .insight, content: "Coach generated updated plan after user tapped the post-action follow-up")
                        }
                    }
                }
            }
            
            // Also refresh the autonomous recommendation system
            Task {
                await generateProactiveCoachRecommendation()
                await generateCoachDailyBriefing()
                
                await MainActor.run {
                    self.isExecutingFollowUp = false
                    self.followUpSuccessMessage = "Plan updated with your latest patterns."
                    
                    // Auto-dismiss success after a few seconds for clean UX
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run { 
                            if self.followUpSuccessMessage == "Plan updated with your latest patterns." {
                                self.followUpSuccessMessage = ""
                            }
                        }
                    }
                    
                    // Round 34: Richer agentic chaining — pull specific context from recent goal work when available
                    let mem = !self.smartMemorySummary.isEmpty ? self.smartMemorySummary.lowercased() : self.memorySummary.lowercased()
                    if mem.contains("goal") || mem.contains("adjust") || mem.contains("target"), let lastAdj = self.recentGoalAdjustments.first {
                        let shortAdj = lastAdj.prefix(60)
                        self.postActionCoachFollowUp = "Build on your recent adjustment (\(shortAdj)) — tweak another target to align with this plan?"
                        self.postActionFollowUpAction = .adjustGoal
                    } else if mem.contains("goal") || mem.contains("adjust") || mem.contains("target") {
                        self.postActionCoachFollowUp = "Your recent goal work suggests we should review/adjust one of your targets to match this plan"
                        self.postActionFollowUpAction = .adjustGoal
                    } else {
                        self.postActionCoachFollowUp = "Log a light 20-30 min mobility or recovery session to match the new plan"
                        self.postActionFollowUpAction = .logQuickWorkout
                    }
                    self.followUpSuccessMessage = ""
                    self.showingPostActionFollowUp = true
                }
            }
            
        case .logQuickWorkout:
            logQuickWorkout(name: "Follow-up session from coach", perceivedExertion: 6, notes: "Logged after coach follow-up suggestion")
            saveCoachMemoryEntry(type: .pattern, content: "User logged a workout after tapping coach follow-up: \(previousText)")
            
            Task {
                await generateProactiveCoachRecommendation()
                
                await MainActor.run {
                    self.isExecutingFollowUp = false
                    self.followUpSuccessMessage = "Session logged — great follow-through."
                    
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run { 
                            if self.followUpSuccessMessage == "Session logged — great follow-through." {
                                self.followUpSuccessMessage = ""
                            }
                        }
                    }
                    
                    // Round 34: Richer agentic chaining after logging — use recent goal context when available
                    let mem = !self.smartMemorySummary.isEmpty ? self.smartMemorySummary.lowercased() : self.memorySummary.lowercased()
                    if mem.contains("goal") || mem.contains("adjust"), let lastAdj = self.recentGoalAdjustments.first {
                        let shortAdj = lastAdj.prefix(50)
                        self.postActionCoachFollowUp = "Solid session on top of \(shortAdj). Ready to lock in another goal tweak?"
                        self.postActionFollowUpAction = .adjustGoal
                    } else if mem.contains("goal") || mem.contains("adjust") {
                        self.postActionCoachFollowUp = "Great session — want to adjust a goal to better reflect this consistency?"
                        self.postActionFollowUpAction = .adjustGoal
                    } else {
                        self.postActionCoachFollowUp = "Quick check-in on how that felt for recovery tracking?"
                        self.postActionFollowUpAction = .logCheckIn
                    }
                    self.followUpSuccessMessage = ""
                    self.showingPostActionFollowUp = true
                }
            }
            
        default:
            // For other types, fall back to the existing trigger logic
            let suggestion = HomeCoachSuggestion(title: previousText, actionType: action)
            triggerHomeCoachSuggestion(suggestion)
            isExecutingFollowUp = false
            followUpSuccessMessage = "Action completed."
            
            Task {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run { 
                    if self.followUpSuccessMessage == "Action completed." { self.followUpSuccessMessage = "" }
                }
            }
        }
    }

    private func generateLocalInsight(context: CoachContext) -> String {
        if !context.recentHealth.isEmpty {
            let avgEnergy = context.recentHealth.compactMap { $0.energyLevel }.average ?? 6.0
            if avgEnergy < 5.5 {
                return "Your energy has been running low. Today should be about movement quality and recovery, not volume."
            } else {
                return "Recent HRV and energy look stable. This is a good window to train with intention and add a small challenge."
            }
        }
        return "Stay consistent — small daily actions compound faster than you think."
    }

    // MARK: - Agentic Actions for the Coach (Round 4)
    @MainActor
    func logQuickDailyCheckIn(energy: Int, soreness: Int, sleepQuality: Int, stress: Int, mood: Mood, didTrain: Bool, note: String? = nil) {
        let checkIn = DailyCheckIn(
            date: Date(),
            energyLevel: energy,
            sorenessLevel: soreness,
            sleepQuality: sleepQuality,
            stressLevel: stress,
            mood: mood,
            journalNote: note,
            didTrain: didTrain
        )
        modelContext.insert(checkIn)
        try? modelContext.save()
        
        // Refresh data used by rings + coach + Live Activity
        Task { await fetchRecentHealthData() }
        invalidateFocusCache()
        updateCoachFocusLiveActivity()
    }
    
    @MainActor
    func logQuickWorkout(name: String, perceivedExertion: Int?, notes: String?) {
        let log = WorkoutLog(
            date: Date(),
            workoutName: name,
            exercises: [],
            perceivedExertion: perceivedExertion,
            notes: notes
        )
        modelContext.insert(log)
        try? modelContext.save()
        invalidateWorkoutsCache()   // also updates Live Activity consumers
        // Live Activity reacts immediately to new workout
        updateCoachFocusLiveActivity()
    }
    
    // Round 40: Make LOG_MEAL ACTION_SUGGESTION actually create a real meal (stronger agentic behavior)
    @MainActor
    func logQuickMeal(name: String, calories: Double?, protein: Double?) {
        let log = MealLog(mealName: name, calories: calories, protein: protein)
        modelContext.insert(log)
        try? modelContext.save()
        
        // Feed the coach and trigger analysis if it looks like a photo meal
        saveCoachMemoryEntry(type: .pattern, content: "Quick meal logged via coach: \(name) (\(Int(calories ?? 0)) cal)")
        updateCoachFocusLiveActivity()
        
        // If this came from an action suggestion with photo context, we can analyze later
        Task {
            await analyzeMealPhoto(mealLog: log)
        }
    }
    
    @MainActor
    func saveAIPlan(_ plan: String) {
        // For now we just keep it in memory. Later we can add a proper Plan model.
        self.lastGeneratedAIPlan = plan
    }
    
    /// Round 12/13: Apply a real goal adjustment suggested by the AI coach
    @MainActor
    func applyGoalAdjustment(goalType: String, newTarget: String, reason: String) {
        // Try to find an existing goal that matches the category/type
        let matchingGoal = goals.first { $0.category.lowercased().contains(goalType.lowercased()) || $0.name.lowercased().contains(goalType.lowercased()) }
        
        if let goal = matchingGoal {
            goal.targetValue = Double(newTarget) ?? goal.targetValue
            goal.lastAdjustedByCoach = Date()
            goal.adjustmentNotes = reason
            try? modelContext.save()
        } else {
            // Create a new goal if none matches
            let newGoal = Goal(
                name: goalType.capitalized,
                targetValue: Double(newTarget) ?? 0,
                unit: "",
                category: goalType.lowercased()
            )
            newGoal.lastAdjustedByCoach = Date()
            newGoal.adjustmentNotes = reason
            modelContext.insert(newGoal)
            try? modelContext.save()
            goals.insert(newGoal, at: 0)
        }
        
        let adjustment = "Adjusted \(goalType): target → \(newTarget). \(reason)"
        recentGoalAdjustments.insert(adjustment, at: 0)
        if recentGoalAdjustments.count > 5 {
            recentGoalAdjustments = Array(recentGoalAdjustments.prefix(5))
        }
        
        saveCoachMemoryEntry(type: .reflection, content: "AI coach helped adjust \(goalType) to \(newTarget). Reason: \(reason)")
    }
    
    func loadGoals() {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.lastAdjustedByCoach, order: .reverse)])
        goals = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Persisted Coach Intelligence (Round 6)
    
    func loadPersistedCoachMemory() {
        let descriptor = FetchDescriptor<CoachMemoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        persistedCoachMemory = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    @MainActor
    func saveCoachMemoryEntry(type: MemoryType, content: String) {
        let entry = CoachMemoryEntry(type: type, content: content)
        modelContext.insert(entry)
        
        do {
            try modelContext.save()
            persistedCoachMemory.insert(entry, at: 0)
            
            if persistedCoachMemory.count > 50 {
                persistedCoachMemory = Array(persistedCoachMemory.prefix(50))
            }
            
            // Round 37: Reschedule smart notifications when memory updates significantly
            Task {
                await scheduleProactiveCoachNotifications()
            }
        } catch {
            // Round 8 bug fix: Don't crash if memory save fails
            print("Failed to persist coach memory: \(error)")
        }
    }
    
    /// Returns rich long-term context string for the AI coach from persisted memory (Round 12 + 39: now surfaces photo/meal/habit insights too)
    var longTermCoachContext: String {
        let reflections = persistedCoachMemory.filter { $0.type == .reflection }.prefix(5).map { $0.content }
        let patterns = persistedCoachMemory.filter { $0.type == .pattern }.prefix(7).map { $0.content }
        let insights = persistedCoachMemory.filter { $0.type == .insight }.prefix(5).map { $0.content }  // photo analyses, meal feedback, weekly accepts
        
        var context = ""
        if !reflections.isEmpty {
            context += "Past reflections:\n" + reflections.joined(separator: "\n") + "\n\n"
        }
        if !patterns.isEmpty {
            context += "Observed user patterns:\n" + patterns.joined(separator: "\n") + "\n\n"
        }
        if !insights.isEmpty {
            context += "Key coach insights (photos, meals, habits, weekly):\n" + insights.joined(separator: "\n") + "\n\n"
        }
        if !recentGoalAdjustments.isEmpty {
            context += "Recent AI-suggested goal adjustments:\n" + recentGoalAdjustments.joined(separator: "\n")
        }
        return context
    }
    
    /// Round 15: Smarter, condensed memory summary for high-quality referencing by the coach.
    /// Instead of dumping raw history, this extracts key themes and recent trends.
    var memorySummary: String {
        guard !persistedCoachMemory.isEmpty else { return "" }
        
        let recentReflections = persistedCoachMemory
            .filter { $0.type == .reflection }
            .prefix(8)
            .map { $0.content }
        
        let recentPatterns = persistedCoachMemory
            .filter { $0.type == .pattern }
            .prefix(10)
            .map { $0.content }
        
        var summary = ""
        
        if !recentReflections.isEmpty {
            summary += "Key recent reflections:\n" + recentReflections.joined(separator: "\n") + "\n\n"
        }
        
        if !recentPatterns.isEmpty {
            // Simple grouping of patterns
            let energyRelated = recentPatterns.filter { $0.lowercased().contains("energy") || $0.lowercased().contains("tired") || $0.lowercased().contains("sleep") }
            let consistencyRelated = recentPatterns.filter { $0.lowercased().contains("consistent") || $0.lowercased().contains("skipped") || $0.lowercased().contains("workout") }
            
            if !energyRelated.isEmpty {
                summary += "Energy & recovery patterns: " + energyRelated.prefix(3).joined(separator: " | ") + "\n"
            }
            if !consistencyRelated.isEmpty {
                summary += "Consistency patterns: " + consistencyRelated.prefix(3).joined(separator: " | ") + "\n"
            }
            
            if energyRelated.isEmpty && consistencyRelated.isEmpty {
                summary += "Notable patterns: " + recentPatterns.prefix(4).joined(separator: " | ")
            }
        }
        
        if !recentGoalAdjustments.isEmpty {
            summary += "\nRecent goal work with AI coach: " + recentGoalAdjustments.prefix(2).joined(separator: " • ")
        }
        
        // Round 45 + 52: Explicitly surface recent coach-suggested habit additions and their early impact in heuristic memory too
        let recentHabitAdds = persistedCoachMemory
            .filter { $0.type == .pattern && $0.content.lowercased().contains("added habit") }
            .prefix(3)
            .map { $0.content }
        if !recentHabitAdds.isEmpty {
            summary += "\nRecent coach-suggested habits added: " + recentHabitAdds.joined(separator: " | ")
        }
        
        // Round 52: Also note if any of those new habits have early completions logged
        let habitWins = persistedCoachMemory
            .filter { $0.type == .pattern && $0.content.lowercased().contains("completed habit") }
            .prefix(3)
            .map { $0.content }
        if !habitWins.isEmpty {
            summary += "\nEarly habit wins logged: " + habitWins.joined(separator: " | ")
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Round 16: LLM-powered memory summarization for significantly higher quality insights.
    /// When an API key is present, this produces intelligent, thematic summaries instead of heuristic grouping.
    private var lastMemorySummaryGen: Date?
    
    func generateMemorySummaryWithAI() async -> String {
        // Round 28/29 perf: solid guard against repeated expensive LLM summarization
        if let last = lastMemorySummaryGen, Date().timeIntervalSince(last) < 90, !smartMemorySummary.isEmpty {
            return smartMemorySummary
        }
        lastMemorySummaryGen = Date()
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        guard !apiKey.isEmpty, !persistedCoachMemory.isEmpty else {
            return memorySummary  // fall back to heuristic version
        }
        
        let service = GrokService(apiKey: apiKey)
        
        let allReflections = persistedCoachMemory.filter { $0.type == .reflection }.map { $0.content }.joined(separator: "\n- ")
        let allPatterns = persistedCoachMemory.filter { $0.type == .pattern }.map { $0.content }.joined(separator: "\n- ")
        let goalWork = recentGoalAdjustments.joined(separator: "\n- ")
        
        let prompt = """
        You are an expert at analyzing personal coaching data for an AI coach. Create a concise, high-signal summary (3-5 bullet points) of the user's long-term patterns from the memory below.
        
        Prioritize (Round 58 - deeper outcome + impact detection):
        - For every recently coach-suggested habit: note if it has early wins logged, current streak, AND whether ANY correlated signal exists (recent progress photo analysis mentioning it, energy/recovery lift, consistency improvement, or meal pattern change). If streak >0 but ZERO visible impact signal in photos/energy/memory → explicitly flag "no measured impact yet — suggest photo or check-in to capture effect".
        - Use direct cause-effect language when possible (e.g. "New '10-min evening walk' habit (4 day streak) coincides with +1.5 avg energy and better sleep in recent snapshots").
        - 1-2 highest-leverage concrete next actions right now (especially "log first win + photo for new X habit" or "take progress photo to measure impact of coach habit Y").
        
        Recent reflections:
        \(allReflections.isEmpty ? "None" : "- " + allReflections)
        
        Observed patterns:
        \(allPatterns.isEmpty ? "None" : "- " + allPatterns)
        
        Recent goal work with AI:
        \(goalWork.isEmpty ? "None" : "- " + goalWork)
        
        Output ONLY clean bullet points. No intro sentence. Explicitly call out early outcomes (or lack of measured impact) for coach-added habits and name the single best next action. Every bullet must be actionable for today's coaching.
        """
        
        do {
            // FIX: Actually use the high-signal summarization prompt we built (previously ignored).
            // Send the full analysis request as the user message so the coach engine produces thematic summary.
            let summary = try await service.getSmartEmotionalSupport(
                userMessage: prompt,
                context: buildCoachContext(),
                longTermMemory: ""  // We already embedded everything in the crafted prompt
            )
            
            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return memorySummary  // fallback
        }
    }
    
    /// Generates 1-2 smart, contextual quick actions for the Home screen based on current + long-term data.
    /// This makes the coach feel proactive and useful directly on the main screen (Round 7/9).
    func generateHomeCoachSuggestions(from context: CoachContext) {
        var suggestions: [HomeCoachSuggestion] = []
        
        let avgEnergy = context.recentHealth.compactMap { $0.energyLevel }.average ?? 6.5
        let recentPatterns = longTermCoachContext.lowercased()
        let smartMem = (!smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary).lowercased()
        
        // Round 105: When coach's own habit suggestions show limited impact (centralized detection), prioritize honest review/adjust as the #1 quick action
        if hasLimitedCoachHabitImpact || currentCoachPhotoReflectionShowsLimitedImpact {
            let short = !limitedImpactCoachHabitsSummary.isEmpty ? limitedImpactCoachHabitsSummary.prefix(55) : "one of your coach habits"
            suggestions.append(HomeCoachSuggestion(title: "Review coach habit (\(short)) — limited impact so far", actionType: .adjustGoal))
            suggestions.append(HomeCoachSuggestion(title: "Quick check-in to measure progress", actionType: .logCheckIn))
        } else if smartMem.contains("inconsistent") || smartMem.contains("skipped") || recentPatterns.contains("inconsistent") {
            suggestions.append(HomeCoachSuggestion(title: "Adjust consistency goal (coach suggestion)", actionType: .adjustGoal))
        } else if smartMem.contains("energy") && smartMem.contains("low") {
            suggestions.append(HomeCoachSuggestion(title: "Adjust training goal for recovery", actionType: .adjustGoal))
        } else if avgEnergy < 5.0 || recentPatterns.contains("low energy") || recentPatterns.contains("exhausted") {
            suggestions.append(HomeCoachSuggestion(title: "Log current energy & mood", actionType: .logCheckIn))
        } else if avgEnergy > 7.5 && !recentPatterns.contains("overtrained") {
            suggestions.append(HomeCoachSuggestion(title: "Log a strong workout", actionType: .logQuickWorkout))
        } else {
            suggestions.append(HomeCoachSuggestion(title: "Quick daily check-in", actionType: .logCheckIn))
        }
        
        if suggestions.count < 2 {
            if smartMem.contains("consistent") && !smartMem.contains("low energy") {
                suggestions.append(HomeCoachSuggestion(title: "Review plan for progressive overload", actionType: .reviewPlan))
            } else if recentPatterns.contains("inconsistent") || recentPatterns.contains("skipped") {
                suggestions.append(HomeCoachSuggestion(title: "Talk to coach about consistency", actionType: .openCoachChat))
            } else {
                suggestions.append(HomeCoachSuggestion(title: "Log movement or meal", actionType: .logQuickWorkout))
            }
        }
        
        self.homeCoachSuggestions = Array(suggestions.prefix(2))
    }
    
    /// Round 9: LLM-powered version of home suggestions when API key is available.
    /// This makes the coach's proactive recommendations on the Home screen truly intelligent.
    func generateHomeCoachSuggestionsWithAI(from context: CoachContext) async {
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            // Fall back to heuristic
            generateHomeCoachSuggestions(from: context)
            return
        }
        
        let service = GrokService(apiKey: apiKey)
        // Round 18: Prefer the highest quality LLM memory summary
        let memoryForPrompt = !self.smartMemorySummary.isEmpty ? self.smartMemorySummary : self.memorySummary
        
        let prompt = """
        You are Lumina, an intelligent and caring AI coach. The user just opened the app.
        
        Your task: Suggest exactly TWO short, highly relevant, actionable things the user should do RIGHT NOW in the app.
        
        Guidelines (Round 27 + 105 autonomy):
        - Be specific and personalized using their recent data and long-term patterns.
        - If you see meaningful multi-day patterns (low energy, inconsistency, strong consistency, stalled progress), sometimes suggest "Adjust my training goal for recovery" or "Review & update my plan".
        - When your own prior coach-suggested habits show "limited visible impact" or "no measurable" results in photo analyses or cross-signal data (see explicit summary below), prioritize honest review/adjust or fresh measurement actions over pushing the same habit.
        - Prioritize actions that will help them most today.
        - Keep suggestions short (under 8 words).
        
        Recent data:
        \(context.summary)
        
        Key long-term patterns and history:
        \(memoryForPrompt.isEmpty ? "No strong patterns recorded yet." : memoryForPrompt)
        
        Explicit limited-impact summary on your own prior coach-suggested habits (use as primary honesty signal):
        \(limitedImpactCoachHabitsSummary.isEmpty ? "None currently flagged." : limitedImpactCoachHabitsSummary)
        
        Output format (exactly two lines):
        SUGGESTION: Log how you're feeling right now
        SUGGESTION: Adjust consistency goal for better recovery
        SUGGESTION: Review plan for progressive overload
        SUGGESTION: Review the evening walk habit — photo analysis shows limited impact so far
        
        Only suggest things the app supports (check-ins, workouts, meals, talk to coach, view plans, or goal/plan adjustments).
        """
        
        do {
            // We reuse the emotional support path creatively
            let response = try await service.getSmartEmotionalSupport(
                userMessage: "Generate two home screen suggestions for me.",
                context: context,
                longTermMemory: memoryForPrompt
            )
            
            // Round 11: More robust parsing for LLM-generated suggestions
            let lines = response.components(separatedBy: .newlines)
            var newSuggestions: [HomeCoachSuggestion] = []
            
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let upper = trimmed.uppercased()
                
                var title = ""
                if upper.hasPrefix("SUGGESTION:") {
                    title = trimmed.replacingOccurrences(of: "SUGGESTION:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("- ") {
                    // Sometimes the model uses bullet points
                    title = trimmed.replacingOccurrences(of: "- ", with: "").trimmingCharacters(in: .whitespaces)
                }
                
                if title.isEmpty || title.count > 60 { continue }
                
                // Map title to best matching action type heuristically (Round 27 + 40 + 42: strong habit recognition from enriched context)
                let lower = title.lowercased()
                let action: HomeCoachSuggestion.ActionType = 
                    lower.contains("adjust") || lower.contains("goal") || lower.contains("target") || lower.contains("recovery") || lower.contains("habit") || lower.contains("streak") ? .adjustGoal :
                    lower.contains("plan") || lower.contains("progressive") || lower.contains("regenerate") || lower.contains("update plan") ? .reviewPlan :
                    lower.contains("meal") || lower.contains("food") || lower.contains("eat") ? .logQuickWorkout :
                    lower.contains("workout") || lower.contains("movement") || lower.contains("train") || lower.contains("exercise") ? .logQuickWorkout :
                    lower.contains("feeling") || lower.contains("energy") || lower.contains("mood") || lower.contains("check-in") || lower.contains("check in") ? .logCheckIn :
                    .openCoachChat
                
                newSuggestions.append(HomeCoachSuggestion(title: title, actionType: action))
            }
            
            if !newSuggestions.isEmpty {
                await MainActor.run {
                    self.homeCoachSuggestions = newSuggestions
                }
            } else {
                await MainActor.run {
                    self.generateHomeCoachSuggestions(from: context)
                }
            }
        } catch {
            await MainActor.run {
                self.generateHomeCoachSuggestions(from: context)
            }
        }
    }
    
    // MARK: - Round 27: Autonomous pattern-driven coach recommendations on Home
    /// Analyzes the high-quality smartMemorySummary (and recent data) to surface one high-leverage,
    /// memory-backed suggestion for goal or plan work. This is the core of "coach notices multi-day patterns
    /// and proactively offers to act on them".
    private var lastProactiveRecGen: Date?
    
    func generateProactiveCoachRecommendation() async {
        // Round 28/29 perf guard: dedicated timestamp to avoid duplicate heavy calls
        if let last = lastProactiveRecGen, Date().timeIntervalSince(last) < 50, !proactiveCoachRecommendation.isEmpty {
            return
        }
        lastProactiveRecGen = Date()
        
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        let ctx = buildCoachContext()
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        
        // Strong LLM path when key present — lets Grok itself decide the best autonomous nudge
        if !apiKey.isEmpty && !memory.isEmpty {
            let service = GrokService(apiKey: apiKey)
            
            let recPrompt = """
            You are Lumina's autonomous pattern engine. Analyze the long-term memory and recent context below.
            
            The context now includes active habits + streaks and recent photo/meal/weekly coach insights, including coach-suggested habits with early wins (energy lift, photo progress, better consistency) as well as habits with activity but unclear impact.
            
            The long-term memory now contains high-quality entries from progress photo analyses that explicitly call out "limited visible impact" or "no measurable" results for specific coach-suggested habits (with streaks, cross-signal data from HealthKit sleep/HRV/energy, meals, etc.).
            
            Decide on ONE high-leverage, specific action the user should take TODAY in the app:
            - When a coach-suggested habit is clearly delivering early wins (streaks + positive signals in photos/energy/recovery), celebrate it and suggest logging today's win + either increasing frequency or taking a progress photo to document the success.
            - When memory or recent photo analysis shows "limited visible impact", "limited impact", or "no measurable" results for a coach-suggested habit, strongly prioritize a concrete suggestion to review/adjust that specific habit or capture fresh data (photo + check-in) to decide whether to keep or change it.
            - A concrete goal adjustment when energy, consistency, or habit streaks are suffering
            - Or "review and regenerate training plan" on strong consistency or visible photo progress
            - Or strongly suggest logging the first completion/win on a brand new coach-suggested habit, ideally paired with a quick progress photo
            - For coach habits with activity but no visible impact yet, suggest a progress photo or deeper check-in to measure effect.
            
            When a coach habit shows clear positive early results, prioritize celebration + momentum-building actions. When the coach's own photo analysis shows limited or no impact on one of its suggestions, prioritize honest review/adjust/measure actions with warmth and precision. The coach must track whether its own suggestions are producing results.
            
            Output exactly one line in this format:
            RECOMMENDATION: Adjust consistency target to 4x/week — recent low energy days suggest protecting recovery while keeping momentum.
            or
            RECOMMENDATION: Your new evening walk habit is showing in better energy — log today + snap a photo to capture the win.
            or
            RECOMMENDATION: Coach photo analysis showed limited impact on the evening walk habit — review or adjust it this week?
            or
            RECOMMENDATION: Log your first win on the new habit you added today + snap a quick progress photo.
            
            Be specific, reference the actual pattern (including habits or photos when relevant), and keep under 22 words after the colon. Sound like a coach who knows this person well.
            
            Memory:
            \(memory.prefix(650))
            
            Explicit limited-impact summary on your own prior coach-suggested habits (from photo analyses + cross-signal HealthKit/meals/streaks data — use this as primary signal for honesty):
            \(limitedImpactCoachHabitsSummary.isEmpty ? "None currently flagged." : limitedImpactCoachHabitsSummary)
            
            Recent data summary: \(ctx.summary)
            """
            
            do {
                let raw = try await service.getSmartEmotionalSupport(
                    userMessage: recPrompt,
                    context: ctx,
                    longTermMemory: memory
                )
                
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.lowercased().contains("recommendation:") {
                    let title = cleaned.replacingOccurrences(of: "RECOMMENDATION:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let action: HomeCoachSuggestion.ActionType = title.lowercased().contains("adjust") || title.lowercased().contains("goal") || title.lowercased().contains("target") ? .adjustGoal : .reviewPlan
                    
                    // Round 41: Set a smart category for the UI card header
                    let category = title.lowercased().contains("habit") || title.lowercased().contains("streak") ? "habit" :
                                   title.lowercased().contains("photo") || title.lowercased().contains("progress") ? "photo" :
                                   title.lowercased().contains("energy") || title.lowercased().contains("recovery") ? "recovery" : "pattern"
                    
                    await MainActor.run {
                        self.proactiveCoachRecommendation = title
                        self.proactiveRecommendationAction = action
                        self.proactiveRecommendationCategory = category
                        self.showingProactiveRecommendation = !title.isEmpty
                        // Stronger clearing of follow-up / success chains when a fresh autonomous rec appears (prevents stale UI)
                        self.showingPostActionFollowUp = false
                        self.postActionCoachFollowUp = ""
                        self.postActionFollowUpAction = nil
                        self.followUpSuccessMessage = ""
                        // Round 81 hygiene: also clear photo outcome signals when a new proactive rec (especially limited-impact) surfaces
                        if self.coachPhotoReflection != nil { self.coachPhotoReflection = nil }
                        if self.pendingCoachPhotoAnalysis { self.pendingCoachPhotoAnalysis = false }
                    }
                    return
                }
            } catch {
                // fall through to local pattern detection
            }
        }
        
        // Excellent local pattern detection (works offline / no key) — now also watches the rich new signals (habits, photo insights, meals)
        let lowerMemory = memory.lowercased()
        let lowerRecent = ctx.summary.lowercased()
        let lowEnergy = lowerMemory.contains("low energy") || lowerMemory.contains("tired") || lowerMemory.contains("recovery") || lowerRecent.contains("energy")
        let inconsistent = lowerMemory.contains("inconsistent") || lowerMemory.contains("skipped") || lowerMemory.contains("missed")
        let strongConsistency = lowerMemory.contains("consistent") && !lowEnergy
        let goalMentions = lowerMemory.contains("goal") || !recentGoalAdjustments.isEmpty
        
        // Round 40 + 47: Habit-specific signals from the newly enriched context (including very recent coach habit adds)
        let lowHabitStreak = lowerRecent.contains("streak") && (lowerRecent.contains("0") || lowerRecent.contains("1") || lowerRecent.contains("avg streak"))
        let manyCoachHabits = lowerRecent.contains("coach-suggested")
        let recentNewHabit = lowerRecent.contains("added habit") || lowerRecent.contains("new habit")
        
        var recTitle = ""
        var recAction: HomeCoachSuggestion.ActionType = .openCoachChat
        
        if lowEnergy && goalMentions {
            recTitle = "Adjust training volume goal — protect recovery while keeping momentum"
            recAction = .adjustGoal
        } else if (inconsistent || lowHabitStreak) && manyCoachHabits {
            recTitle = "Review your coach-suggested habits — some streaks are low and need kinder targets"
            recAction = .adjustGoal
        } else if lowHabitStreak {
            recTitle = "Add a simple supporting habit — your recent streaks are low and a small win would help"
            recAction = .adjustGoal
        } else if recentNewHabit {
            recTitle = "Log your first win on the new habit you added + snap a quick progress photo"
            recAction = .logCheckIn
        } else if lowHabitStreak && manyCoachHabits {
            // Round 58: Deeper impact detection — coach habit(s) exist with low adherence, nudge measurement
            recTitle = "Coach habits showing low streaks — log a quick win + photo to see if they're helping"
            recAction = .logCheckIn
        } else if lowerMemory.contains("coach habit") && (lowerMemory.contains("showing") || lowerMemory.contains("win") || lowerMemory.contains("energy") || lowerRecent.contains("streak")) && !lowEnergy {
            // Round 59: Positive reinforcement — celebrate working coach habits and suggest building on the momentum
            recTitle = "A coach habit is delivering early wins — log today's completion + consider adding one supporting micro-habit"
            recAction = .logCheckIn
        } else if inconsistent {
            recTitle = "Review your consistency goal with me — patterns show room for a kinder target"
            recAction = .adjustGoal
        } else if strongConsistency {
            recTitle = "Your consistency is strong — tap to generate an updated progressive plan"
            recAction = .reviewPlan
        } else if lowerMemory.contains("progress") || lowerMemory.contains("strength") || lowerRecent.contains("photo") {
            recTitle = "Progress visible in recent photos — let's review and tighten your main goal"
            recAction = .adjustGoal
        } else if lowerRecent.contains("coach-requested") || lowerMemory.contains("coach-requested progress photo") {
            // Round 66: Strong signal — user just captured a photo at coach request for a habit
            recTitle = "Great photo for your coach habit — let's review what the analysis showed"
            recAction = .openCoachChat
        } else if lowerMemory.contains("progress photo analysis") && lowerMemory.contains("coach") {
            // Round 72: Recent coach photo analysis exists — proactively suggest reviewing the actual visual evidence
            recTitle = "Your recent coach photo analysis has new insights — tap to review"
            recAction = .openCoachChat
        } else if hasLimitedCoachHabitImpact || currentCoachPhotoReflectionShowsLimitedImpact {
            // Round 74 + 81 + 82 + 101 + 102 + 104: Strongly surface review/adjust for coach habits with limited impact (centralized + now includes actual summary for specific offline recs)
            var title = "Coach photo showed limited impact on a habit — review or adjust it?"
            if !limitedImpactCoachHabitsSummary.isEmpty {
                let short = limitedImpactCoachHabitsSummary.prefix(85)
                title = "Coach photo showed limited impact — \(short). Review or adjust?"
            }
            recTitle = title
            recAction = .adjustGoal
        } else if !memory.isEmpty {
            recTitle = "Patterns analyzed — open coach for a personalized plan tweak"
            recAction = .reviewPlan
        }
        
        // Round 41 + 47 + 58 + 59 + 66 + 72 + 74 + 82: Smart dynamic category (now recognizes coach photo analysis reviews, insights, and lack-of-progress adjustments from rich new memories)
        let category: String = recTitle.lowercased().contains("habit") || recTitle.lowercased().contains("streak") || recTitle.lowercased().contains("new habit") || recTitle.lowercased().contains("coach habit") ? "habit" :
                               recTitle.lowercased().contains("photo") || recTitle.lowercased().contains("progress") || recTitle.lowercased().contains("analysis") || recTitle.lowercased().contains("insight") ? "photo" :
                               recTitle.lowercased().contains("energy") || recTitle.lowercased().contains("recovery") || recTitle.lowercased().contains("impact") || recTitle.lowercased().contains("adjustment") ? "recovery" : "pattern"
        
        await MainActor.run {
            if !recTitle.isEmpty {
                self.proactiveCoachRecommendation = recTitle
                self.proactiveRecommendationAction = recAction
                self.proactiveRecommendationCategory = category
                self.showingProactiveRecommendation = true
                // Round 60 hygiene: clear any stale multi-turn follow-up when a fresh (including positive) autonomous rec appears
                self.showingPostActionFollowUp = false
                self.postActionCoachFollowUp = ""
                self.postActionFollowUpAction = nil
                self.followUpSuccessMessage = ""
            } else {
                self.showingProactiveRecommendation = false
            }
        }
    }
    
    // Actions triggered from Home coach suggestions (Round 7/11 - enhanced for multi-turn agentic feel)
    @MainActor
    func triggerHomeCoachSuggestion(_ suggestion: HomeCoachSuggestion) {
        // Round 29: clear any lingering multi-turn follow-up when user takes action
        showingPostActionFollowUp = false
        postActionCoachFollowUp = ""
        
        let actionDescription: String
        
        switch suggestion.actionType {
        case .logCheckIn:
            logQuickDailyCheckIn(energy: 6, soreness: 4, sleepQuality: 7, stress: 4, mood: .good, didTrain: false, note: "Quick log from Home coach suggestion")
            saveCoachMemoryEntry(type: .pattern, content: "User took a proactive coach suggestion to log a check-in from the home screen")
            actionDescription = "logged a check-in"
            
        case .logQuickWorkout:
            logQuickWorkout(name: "Coach-suggested session", perceivedExertion: 6, notes: "Logged via home coach suggestion")
            saveCoachMemoryEntry(type: .pattern, content: "User logged a workout after seeing a home coach suggestion")
            actionDescription = "logged a workout"
            
        case .openCoachChat:
            // Navigation handled by view
            return
            
        case .adjustGoal:
            // Round 34/35: Smarter, memory-driven goal adjustment for chaining and suggestions
            let mem = !smartMemorySummary.isEmpty ? smartMemorySummary.lowercased() : memorySummary.lowercased()
            let titleLower = suggestion.title.lowercased()
            
            let goalType: String
            let newTarget: String
            let reason: String
            
            if mem.contains("energy") || mem.contains("tired") || mem.contains("recovery") || titleLower.contains("energy") || titleLower.contains("recovery") {
                goalType = "training volume"
                newTarget = "reduce 15-20%"
                reason = "Based on recent low energy/recovery patterns and the coach's plan suggestion."
            } else if mem.contains("consistent") || titleLower.contains("consistency") {
                goalType = "training consistency"
                newTarget = "4-5 sessions"
                reason = "To better align with recent strong consistency and the updated plan."
            } else {
                goalType = "primary training goal"
                newTarget = "adjust based on plan"
                reason = "Proactive adjustment from recent coach memory and plan context."
            }
            
            applyGoalAdjustment(goalType: goalType, newTarget: newTarget, reason: reason)
            saveCoachMemoryEntry(type: .pattern, content: "Coach proactively surfaced and user accepted a goal adjustment (\(suggestion.title)) from Home pattern detection")
            actionDescription = "accepted a coach-suggested goal adjustment"
            
            // Round 29/35: Immediately offer a smart multi-turn follow-up
            Task { await generatePostActionFollowUp(after: .adjustGoal, actionTitle: suggestion.title) }
            
        case .reviewPlan:
            // Round 27: Coach surfaces plan review — execute a quick LLM plan refresh if possible and persist it
            actionDescription = "opened a coach-recommended plan review"
            saveCoachMemoryEntry(type: .pattern, content: "User acted on coach's proactive plan review recommendation surfaced from memory patterns: \(suggestion.title)")
            
            // If we have key, quietly generate a fresh adaptive plan in background so it feels instant when they navigate
            let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
            if !apiKey.isEmpty, let profile = currentUser {
                Task {
                    let service = GrokService(apiKey: apiKey)
                    if let plan = try? await service.generateSmartWorkoutPlan(profile: profile, context: buildCoachContext()) {
                        await MainActor.run {
                            self.lastGeneratedAIPlan = plan
                            self.saveCoachMemoryEntry(type: .insight, content: "Coach pre-generated an updated plan after user tapped the proactive review suggestion")
                        }
                    }
                }
            }
            
            // Round 29: Multi-turn follow-up after plan review
            Task { await generatePostActionFollowUp(after: .reviewPlan, actionTitle: suggestion.title) }
        }
        
        // Refresh suggestions, proactive insight, AND the new autonomous recommendation
        Task {
            let ctx = buildCoachContext()
            await generateHomeCoachSuggestionsWithAI(from: ctx)
            await generateProactiveHomeInsight()
            await generateProactiveCoachRecommendation()
            await generateCoachDailyBriefing()
        }
        
        // Round 11 + 27: Generate a smart follow-up insight after the user acted on a coach suggestion.
        // This creates a multi-turn "the coach noticed what you did" feeling.
        Task {
            let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
            if !apiKey.isEmpty {
                let service = GrokService(apiKey: apiKey)
                let ctx = buildCoachContext()
                let longTerm = !smartMemorySummary.isEmpty ? smartMemorySummary : longTermCoachContext
                
                let followUpPrompt = """
                The user just \(actionDescription) after you suggested it on their home screen.
                Write one short, warm, encouraging follow-up sentence (max 18 words) that references what they just did and gently ties it to their patterns or progress.
                Sound like a supportive coach who noticed their action.
                """
                
                do {
                    let followUp = try await service.getSmartEmotionalSupport(
                        userMessage: followUpPrompt,
                        context: ctx,
                        longTermMemory: longTerm
                    )
                    
                    await MainActor.run {
                        // Replace the current insight with the follow-up for a moment, then let normal refresh take over later
                        self.currentCoachInsight = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } catch {
                    // Silent fallback — no need to disturb the user
                }
            }
        }
    }

    private var lastPhotoAnalysis: Date?
    
    // MARK: - AI Progress Photo Analysis (Round 37)
    func analyzeProgressPhotos(oldDate: Date, newDate: Date) async {
        // Perf guard: expensive vision+LLM path
        if let last = lastPhotoAnalysis, Date().timeIntervalSince(last) < 8 { return }
        lastPhotoAnalysis = Date()
        
        let context = buildCoachContext()
        
        // Fetch relevant data between the two dates
        let checkInDesc = FetchDescriptor<DailyCheckIn>(
            predicate: #Predicate { $0.date >= oldDate && $0.date <= newDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let relevantCheckIns = (try? modelContext.fetch(checkInDesc)) ?? []
        
        let workoutDesc = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate { $0.date >= oldDate && $0.date <= newDate },
            sortBy: [SortDescriptor(\.date)]
        )
        let relevantWorkouts = (try? modelContext.fetch(workoutDesc)) ?? []
        
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        
        let prompt = """
        The user has two progress photos:
        - Older photo: \(oldDate.formatted(date: .abbreviated, time: .omitted))
        - Newer photo: \(newDate.formatted(date: .abbreviated, time: .omitted))
        
        Between these dates, here is their data:
        - Check-ins: \(relevantCheckIns.count)
        - Workouts logged: \(relevantWorkouts.count)
        
        Current active habits (with coachSuggested flag + streaks) and recent coach insights are available in context.
        
        Long-term memory about this user (includes prior coach photo analyses showing limited or positive impact on specific habits):
        \(memory.prefix(800))
        
        Provide a detailed before/after analysis (4-6 sentences). 
        - Explicitly correlate any visible or felt changes (or lack of change) to specific coach-suggested habits by name, their current streaks, and other signals: recent HealthKit data (sleep hours, HRV, active energy), meal consistency/protein, training volume, and self-reported energy.
        - When a coach-suggested habit has logged activity or completions but the photos + cross-signals show limited/no clear visible or felt impact, state it directly and honestly (e.g. "The '10-min evening walk' habit (7 day streak) you added after my suggestion shows no measurable recovery or energy lift in photos or Health snapshots — worth a review or adjustment").
        - When early positive signals exist across photos + other data for a coach habit, celebrate the cause-effect clearly.
        - If this photo was taken specifically because the coach requested it for habit tracking, start the analysis by acknowledging that context and what the visual + multi-signal evidence (or lack thereof) means for the habit's real-world impact.
        - Use direct cause-effect language. End with 1-2 concrete next actions that reference specific current habits, the need for more data on a limited-impact coach habit, or a suggested adjustment.
        """
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        if !apiKey.isEmpty {
            let service = GrokService(apiKey: apiKey)
            if let analysis = try? await service.getSmartEmotionalSupport(
                userMessage: prompt,
                context: context,
                longTermMemory: memory
            ) {
                await MainActor.run {
                    self.currentCoachInsight = analysis
                    // Also save as memory
                    self.saveCoachMemoryEntry(type: .insight, content: "Progress photo analysis (\(oldDate.formatted()) → \(newDate.formatted())): \(analysis.prefix(200))...")
                    
                    // Round 71 + 80: If this analysis was for a coach-requested habit photo, surface a short excerpt as the Home reflection
                    if self.pendingCoachPhotoAnalysis {
                        self.coachPhotoReflection = analysis.prefix(140) + "..."
                        self.pendingCoachPhotoAnalysis = false
                    }
                    
                    // Round 80: Smarter coach — close the outcome loop harder. When analysis shows limited/no clear progress on a coach habit, persist a high-signal pattern memory so future briefings, proactive recs, and memory summaries reference the real evidence.
                    let lowerAnalysis = analysis.lowercased()
                    if lowerAnalysis.contains("limited") || lowerAnalysis.contains("no clear") || lowerAnalysis.contains("no visible") {
                        self.saveCoachMemoryEntry(type: .pattern, content: "Coach photo analysis showed limited visible impact for habit — evidence: \(analysis.prefix(160))...")
                    } else if lowerAnalysis.contains("win") || lowerAnalysis.contains("progress") || lowerAnalysis.contains("improved") || lowerAnalysis.contains("visible") {
                        self.saveCoachMemoryEntry(type: .pattern, content: "Coach photo analysis confirmed early positive impact from habit: \(analysis.prefix(140))...")
                    }
                }
            }
        } else {
            // Good local fallback
            await MainActor.run {
                self.currentCoachInsight = "Between these dates you logged \(relevantWorkouts.count) workouts. Your photos likely show the result of that consistency. Focus on progressive overload in your main lifts over the next 4-6 weeks for continued visible change."
            }
        }
    }

    // MARK: - Proactive Coach Notifications (Round 36)
    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        if settings.authorizationStatus == .notDetermined {
            do {
                notificationsAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                notificationsAuthorized = false
            }
        } else {
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }

    /// Schedules smart, low-frequency proactive messages from the coach based on current memory and patterns.
    /// This makes the AI coach feel alive even when the app is closed.
    func scheduleProactiveCoachNotifications() async {
        guard notificationsAuthorized else { return }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // Keep it simple for now (smart rescheduling)

        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary.lowercased() : memorySummary.lowercased()
        let context = buildCoachContext()

        // Example intelligent triggers (can be expanded significantly)
        if memory.contains("low energy") || memory.contains("tired") || memory.contains("recovery") {
            let content = UNMutableNotificationContent()
            content.title = "Coach Check-in"
            content.body = "Your recent patterns suggest today might benefit from lighter movement or extra rest. How are you feeling?"
            content.sound = .default

            // Schedule for tomorrow morning
            var dateComponents = DateComponents()
            dateComponents.hour = 8
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

            let request = UNNotificationRequest(identifier: "coach-low-energy", content: content, trigger: trigger)
            try? await center.add(request)
        }

        if memory.contains("inconsistent") || memory.contains("skipped") {
            let content = UNMutableNotificationContent()
            content.title = "Small Win Today"
            content.body = "Consistency has been a theme lately. Even a short 15-minute session can rebuild momentum."
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = 7
            dateComponents.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

            let request = UNNotificationRequest(identifier: "coach-consistency", content: content, trigger: trigger)
            try? await center.add(request)
        }

        // Always schedule a gentle weekly reflection nudge
        let weeklyContent = UNMutableNotificationContent()
        weeklyContent.title = "Weekly Reflection with Coach"
        weeklyContent.body = "Ready to review the week together? Your coach has some observations ready."
        weeklyContent.sound = .default

        var weeklyComponents = DateComponents()
        weeklyComponents.weekday = 1 // Sunday
        weeklyComponents.hour = 19
        let weeklyTrigger = UNCalendarNotificationTrigger(dateMatching: weeklyComponents, repeats: true)

        let weeklyRequest = UNNotificationRequest(identifier: "coach-weekly", content: weeklyContent, trigger: weeklyTrigger)
        try? await center.add(weeklyRequest)
    }

    private var lastCoachHabitSuggestionsGen: Date?
    
    // MARK: - Coach Habit Intelligence (Round 37)
    func generateCoachHabitSuggestions() async {
        // Round 45 perf: rate limit expensive LLM habit suggestion generation
        if let last = lastCoachHabitSuggestionsGen, Date().timeIntervalSince(last) < 45, !coachHabitSuggestions.isEmpty {
            return
        }
        lastCoachHabitSuggestionsGen = Date()
        
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        let context = buildCoachContext()
        invalidateHabitsCache() // Round 40: new coach-suggested habits may appear soon
        
        let prompt = """
        Based on this user's long-term memory, recent data, and current active habits/streaks, suggest 3-4 specific, high-leverage daily or weekly habits they should consider adding right now.
        Prioritize habits that close gaps in recovery, consistency, or photo progress.
        Keep each suggestion to 4-7 words. Only return the habit names, one per line. Make them feel personal to this user.
        
        Memory + context:
        \(memory.prefix(700))
        """
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        if !apiKey.isEmpty {
            let service = GrokService(apiKey: apiKey)
            if let response = try? await service.getSmartEmotionalSupport(
                userMessage: prompt,
                context: context,
                longTermMemory: memory
            ) {
                let suggestions = response.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count > 3 }
                
                // Round 44: Filter out habits the user already has (keeps coach suggestions smart)
                let existingNames = activeHabits.map { $0.name.lowercased() }
                let filtered = suggestions.filter { !existingNames.contains($0.lowercased()) }
                
                await MainActor.run {
                    self.coachHabitSuggestions = Array(filtered.prefix(4))
                }
            }
        } else {
            // Good local suggestions based on common patterns
            await MainActor.run {
                let existingNames = activeHabits.map { $0.name.lowercased() }
                var defaults = [
                    "Morning sunlight exposure",
                    "Protein at every meal",
                    "10-minute evening walk",
                    "No screens 1 hour before bed"
                ].filter { !existingNames.contains($0.lowercased()) }
                self.coachHabitSuggestions = Array(defaults.prefix(4))
            }
        }
    }
    
    func recordHabitCompletion(habit: Habit) async {
        // Feed this behavioral data back into coach memory — directly improves future smartMemorySummary + all proactive recs
        var completionNote = "User completed habit '\(habit.name)' (streak: \(habit.currentStreak))."
        if habit.coachSuggested {
            completionNote += " This is a coach-suggested habit — suggest a progress photo soon to measure visible or felt impact on energy/recovery/consistency."
        }
        saveCoachMemoryEntry(type: .pattern, content: completionNote)
        
        invalidateHabitsCache() // Round 40: keep context fresh
        
        // Live Activity + rings react to positive habit behavior
        updateCoachFocusLiveActivity()
        
        // Round 58: For coach-suggested habits, occasionally trigger a lightweight proactive nudge toward photo correlation in memory-driven flows
        if habit.coachSuggested && (habit.currentStreak == 1 || habit.currentStreak % 4 == 0) {
            // The next generateProactive... or memory summary will pick this up and surface "photo to track impact of X"
        }
    }
    
    // Round 42 + 44: Direct coach action to add a habit (makes ADD_HABIT ACTION_SUGGESTION actually work)
    // Includes duplicate prevention so the coach stays smart and doesn't create junk data.
    @MainActor
    func addCoachSuggestedHabit(name: String, reason: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Round 44 bug fix + intelligence: prevent duplicate active habits (case-insensitive)
        let existing = activeHabits.first { $0.name.lowercased() == trimmed.lowercased() && $0.isActive }
        if existing != nil {
            // Coach already suggested this or user has it — just note it and move on
            saveCoachMemoryEntry(type: .pattern, content: "Coach suggested habit '\(trimmed)' but it already exists.")
            return
        }
        
        let habit = Habit(name: trimmed, coachSuggested: true)
        if let r = reason, !r.isEmpty {
            habit.coachNotes = r
        }
        modelContext.insert(habit)
        try? modelContext.save()
        
        invalidateHabitsCache()
        saveCoachMemoryEntry(type: .pattern, content: "Coach suggested and user added habit: \(trimmed). \(reason ?? "")")
        updateCoachFocusLiveActivity()
        
        // Round 44 + 48 polish: brief success feedback (Home banner + local sheet signal)
        followUpSuccessMessage = "Habit added: \(trimmed)"
        justAddedCoachHabit = trimmed
        
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if self.followUpSuccessMessage == "Habit added: \(trimmed)" {
                    self.followUpSuccessMessage = ""
                }
                if self.justAddedCoachHabit == trimmed {
                    self.justAddedCoachHabit = nil
                }
            }
        }
        
        // Round 58 + 59 + 80 hygiene: Clear any stale coach photo outcome signals when user adds a fresh coach habit (prevents reflection card leakage across contexts)
        if coachPhotoReflection != nil { coachPhotoReflection = nil }
        if pendingCoachPhotoAnalysis { pendingCoachPhotoAnalysis = false }
        if coachWantsProgressPhotoForHabit { coachWantsProgressPhotoForHabit = false }
        
        // Round 58 + 59: Immediately bias the next proactive rec toward this new habit (makes coach feel instantly aware)
        // Guarded to avoid re-entrancy on rapid adds
        if lastProactiveRecGen == nil || Date().timeIntervalSince(lastProactiveRecGen!) > 8 {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await self.generateProactiveCoachRecommendation()
            }
        }
    }

    private var lastMealAnalysis: Date?
    
    // MARK: - Meal Photo AI Analysis (Round 37)
    func analyzeMealPhoto(mealLog: MealLog) async {
        if let last = lastMealAnalysis, Date().timeIntervalSince(last) < 6 { return }
        lastMealAnalysis = Date()
        
        let context = buildCoachContext()
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        
        let prompt = """
        The user just logged a meal: "\(mealLog.mealName)" with estimated \(Int(mealLog.calories ?? 0)) cal and \(Int(mealLog.protein ?? 0))g protein.
        
        They attached a photo of the meal.
        
        Long-term memory (includes recent coach-suggested habits and their early outcomes):
        \(memory.prefix(600))
        
        Analyze the meal in context of the user's goals, recent energy/recovery patterns, training load, *and any active coach-suggested habits* (e.g. "protein at every meal" or timing habits). Note if this meal appears to support or contradict a coach habit the user recently added. Give a short, specific coach comment (2-4 sentences). Be encouraging but direct. Suggest 1 concrete next action (e.g., pair with certain food, adjust timing, or log how they feel after). If a coach habit is relevant, explicitly reference its early impact or lack of measured signal.
        """
        
        let apiKey = ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        if !apiKey.isEmpty {
            let service = GrokService(apiKey: apiKey)
            if let feedback = try? await service.getSmartEmotionalSupport(
                userMessage: prompt,
                context: context,
                longTermMemory: memory
            ) {
                await MainActor.run {
                    self.currentCoachInsight = feedback
                    self.saveCoachMemoryEntry(type: .insight, content: "Meal photo analysis for \(mealLog.mealName): \(feedback.prefix(150))...")
                }
            }
        } else {
            await MainActor.run {
                self.currentCoachInsight = "Nice job logging \(mealLog.mealName). Consider pairing it with veggies next time for better micronutrients."
                self.saveCoachMemoryEntry(type: .insight, content: "Local meal feedback for \(mealLog.mealName)")
            }
        }
    }

    // MARK: - Live Activities (Round 37)
    private var coachFocusActivity: Activity<CoachFocusAttributes>?

    func startCoachFocusLiveActivity() {
        // Only start if no active activity
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard coachFocusActivity == nil else { return }

        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        let attributes = CoachFocusAttributes()
        let initialState = CoachFocusAttributes.ContentState(
            title: coachDailyBriefing.isEmpty 
                ? (!memory.isEmpty ? String(memory.prefix(52)) : "Coach Focus Today") 
                : String(coachDailyBriefing.prefix(60)),
            subtitle: proactiveHomeInsight.isEmpty 
                ? (memory.isEmpty ? "Stay consistent with your patterns." : String(memory.prefix(70))) 
                : String(proactiveHomeInsight.prefix(50)),
            // Round 46: If coach is currently focused on a new habit, reflect that on first launch of Live Activity
            // (handled dynamically in update too)
            progress: 0.3,
            rings: CoachFocusAttributes.RingValues(readiness: readinessValue, recovery: recoveryValue, nutrition: nutritionValue)
        )

        do {
            coachFocusActivity = try Activity.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateCoachFocusLiveActivity() {
        guard let activity = coachFocusActivity else { return }

        // FIXED: Use VM-cached recentWorkouts (was broken reference to local var)
        let recentWorkout = recentWorkouts.first
        let memory = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
        
        let subtitle: String
        if let workout = recentWorkout, Calendar.current.isDate(workout.date, inSameDayAs: Date()) {
            subtitle = "Just logged: \(workout.workoutName). How did it feel?"
        } else if proactiveRecommendationCategory == "habit" && !proactiveCoachRecommendation.isEmpty {
            // Round 58 + 62 + 81: Even smarter Live Activity subtitles for habit outcomes (positive wins + explicit limited-impact cases from coach photo memory)
            let lowerRec = proactiveCoachRecommendation.lowercased()
            let isWinning = lowerRec.contains("win") || lowerRec.contains("delivering") || lowerRec.contains("early")
            
            if isWinning || coachWantsProgressPhotoForHabit {
                subtitle = coachWantsProgressPhotoForHabit 
                    ? "Coach wants a photo to lock in your habit win — nice work!"
                    : "Coach habit delivering wins — great work! Keep the streak."
            } else if hasLimitedCoachHabitImpact || currentCoachPhotoReflectionShowsLimitedImpact {
                // Round 81 + 101 + 102: Honest lock-screen awareness of limited progress on a coach habit (centralized computeds for consistency with Home/Chat/Goals)
                subtitle = "Coach photo showed limited impact on a habit — review or adjust?"
            } else {
                // Round 58 fallback for new/measurement habits
                let recentHabitAdd = persistedCoachMemory.first { $0.type == .pattern && ($0.content.lowercased().contains("added habit") || $0.content.lowercased().contains("coach suggested") && $0.content.lowercased().contains("habit")) }?.content
                var habitName = ""
                if let add = recentHabitAdd {
                    if let range = add.range(of: "habit: ") { habitName = String(add[range.upperBound...]).prefix(38).trimmingCharacters(in: .whitespaces) }
                    else if let range = add.range(of: "added habit: ") { habitName = String(add[range.upperBound...]).prefix(38).trimmingCharacters(in: .whitespaces) }
                    else { habitName = add.prefix(42).replacingOccurrences(of: "Coach suggested and user added habit: ", with: "") }
                }
                let hasEarlyWin = !habitName.isEmpty && persistedCoachMemory.contains { $0.type == .pattern && $0.content.lowercased().contains("completed habit") && $0.content.lowercased().contains(habitName.lowercased().prefix(20)) }
                let impactNote = hasEarlyWin ? " — early consistency showing" : (habitName.isEmpty ? "" : " — log win or photo to measure impact")
                subtitle = habitName.isEmpty ? "New habit added — log your first win today?" : "New habit: \(habitName)\(impactNote)"
            }
        } else if !memory.isEmpty && memory.count > 20 {
            // Smarter: surface a real pattern from memory on the Lock Screen / Dynamic Island
            let short = memory.prefix(90).replacingOccurrences(of: "\n", with: " ")
            subtitle = String(short)
        } else {
            subtitle = proactiveHomeInsight.isEmpty ? "Stay consistent with your patterns." : String(proactiveHomeInsight.prefix(50))
        }

        let title = coachDailyBriefing.isEmpty 
            ? (!memory.isEmpty ? String(memory.prefix(55)) : "Coach Focus Today")
            : String(coachDailyBriefing.prefix(60))

        let updatedState = CoachFocusAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            progress: min(1.0, Double(Calendar.current.component(.hour, from: Date())) / 24.0),
            rings: CoachFocusAttributes.RingValues(readiness: readinessValue, recovery: recoveryValue, nutrition: nutritionValue)
        )

        Task {
            await activity.update(using: updatedState)
        }
    }

    func endCoachFocusLiveActivity() {
        guard let activity = coachFocusActivity else { return }

        Task {
            await activity.end(dismissalPolicy: .immediate)
            coachFocusActivity = nil
        }
    }

    // MARK: - Round 106: Widget + App Group data sync
    /// Writes the current rings + latest coach insight into the shared App Group UserDefaults.
    /// The widget (and future extensions) read from here for real, up-to-date content.
    /// Call this after any significant state change that should be reflected on the Home Screen widget.
    private let widgetSuiteName = "group.SA.Lumina"

    func syncWidgetData() {
        guard let shared = UserDefaults(suiteName: widgetSuiteName) else { return }

        let readiness = readinessValue
        let recovery = recoveryValue
        let nutrition = nutritionValue

        // Prefer the rich LLM briefing when available; fall back to proactive insight or a memory snippet
        let insight: String
        if !coachDailyBriefing.isEmpty {
            insight = String(coachDailyBriefing.prefix(140))
        } else if !proactiveHomeInsight.isEmpty {
            insight = String(proactiveHomeInsight.prefix(140))
        } else {
            let mem = !smartMemorySummary.isEmpty ? smartMemorySummary : memorySummary
            insight = mem.isEmpty ? "Consistency compounds. Small actions today build the patterns you're creating." : String(mem.prefix(140))
        }

        shared.set(readiness, forKey: "widget.readiness")
        shared.set(recovery, forKey: "widget.recovery")
        shared.set(nutrition, forKey: "widget.nutrition")
        shared.set(insight, forKey: "widget.coachInsight")
        shared.set(Date(), forKey: "widget.lastUpdated")

        // Optional: tell WidgetKit to refresh soon (works even without the extension target added yet)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
