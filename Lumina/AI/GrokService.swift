import Foundation

struct GrokService {
    // Retained for older call sites. Paid/cloud coaching is retired in every
    // configuration; environment variables and saved credentials are untouched.
    static var configuredAPIKey: String? { nil }

    private let smartCoach = SmartGrokCoach()

    init(apiKey _: String = "") { }

    /// Deterministic local compatibility path; the current chat uses OnDeviceCoach.
    func getSmartEmotionalSupport(userMessage: String, context: CoachContext, longTermMemory: String = "") async throws -> String {
        try await smartCoach.respondToUser(message: userMessage, context: context, longTermMemory: longTermMemory)
    }
    
    /// Older callers receive local guidance without automatic record actions.
    func getAgenticCoachReply(userMessage: String, context: CoachContext) async throws -> String {
        try await smartCoach.respondToUser(message: userMessage, context: context)
    }

    /// Legacy thin-context local guidance.
    func getEmotionalSupport(userMessage: String, recentHealth: [HealthSnapshot], profile: UserProfile? = nil) async throws -> String {
        let context = CoachContext(
            profile: profile,
            recentHealth: recentHealth,
            recentCheckIns: [],
            recentWorkouts: [],
            recentMeals: [],
            activeHabits: [],
            recentInsights: [],
            currentStreak: 0
        )
        let coach = SmartGrokCoach()
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
