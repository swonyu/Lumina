import Foundation

struct GrokService {
    private var smartCoach: SmartGrokCoach

    init(apiKey: String = "") {
        self.smartCoach = SmartGrokCoach(apiKey: apiKey)
    }

    mutating func getSmartEmotionalSupport(userMessage: String, context: CoachContext) async throws -> String {
        try await smartCoach.respondToUser(message: userMessage, context: context)
    }

    func getEmotionalSupport(userMessage: String, recentHealth: [HealthSnapshot], profile: UserProfile? = nil) async throws -> String {
        let context = CoachContext(
            profile: profile,
            recentHealth: recentHealth,
            recentCheckIns: [],
            recentWorkouts: [],
            recentMeals: [],
            currentStreak: 0
        )
        var coach = SmartGrokCoach()
        return try await coach.respondToUser(message: userMessage, context: context)
    }

    func generateSmartWorkoutPlan(profile: UserProfile, context: CoachContext) async throws -> String {
        try await smartCoach.generateSmartWorkoutPlan(profile: profile, context: context)
    }

    func getWeeklyReflection(context: CoachContext, workoutsCompleted: Int, avgEnergy: Double) async throws -> String {
        try await smartCoach.generateWeeklyReflection(
            context: context,
            workoutsCompleted: workoutsCompleted,
            avgEnergy: avgEnergy
        )
    }
}
