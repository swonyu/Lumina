import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class LuminaViewModel {
    var currentUser: UserProfile?
    var recentHealthSnapshots: [HealthSnapshot] = []
    var isLoadingHealthData = false
    var errorMessage: String?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCurrentUser()
        
        // Auto-create a demo profile on first launch so the app feels alive
        if currentUser == nil {
            createDemoProfile()
        }
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

    func requestHealthKitAccess() async {
        isLoadingHealthData = true
        errorMessage = "HealthKit is not configured in this build."
        isLoadingHealthData = false
    }

    func fetchRecentHealthData() async {
        isLoadingHealthData = true
        var descriptor = FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 14
        recentHealthSnapshots = (try? modelContext.fetch(descriptor)) ?? []
        isLoadingHealthData = false
    }

    func getRecentHealthContextForAI() -> [HealthSnapshot] {
        Array(recentHealthSnapshots.prefix(7))
    }
    
    // Simple demo helper for Home "Today's Focus"
    var todaysFocusWorkout: String {
        var descriptor = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        if let recent = try? modelContext.fetch(descriptor).first {
            return recent.workoutName
        }
        return "Push + Core"
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
    
    var coachInsightText: String {
        if !recentHealthSnapshots.isEmpty {
            return "Your recent HRV trend looks solid. Great window to push a bit harder if energy stays good."
        }
        return "Stay consistent — small daily actions compound faster than you think."
    }
}
