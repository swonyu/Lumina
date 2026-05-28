import Foundation

struct GrokService {
    private var smartCoach: SmartGrokCoach
    private let apiKey: String

    init(apiKey: String = "") {
        self.apiKey = apiKey
        self.smartCoach = SmartGrokCoach(apiKey: apiKey)
    }

    /// Preferred rich-context smart coach path (uses full LLM + memory + excellent prompts)
    func getSmartEmotionalSupport(userMessage: String, context: CoachContext, longTermMemory: String = "") async throws -> String {
        try await smartCoach.respondToUser(message: userMessage, context: context, longTermMemory: longTermMemory)
    }
    
    /// Version optimized for agentic behavior — the coach will sometimes suggest concrete actions the app can take.
    func getAgenticCoachReply(userMessage: String, context: CoachContext) async throws -> String {
        // We reuse the core engine but can later extend SmartGrokCoach with a dedicated agentic prompt.
        try await smartCoach.respondToUser(message: userMessage, context: context)
    }

    /// Legacy / thin context path (now also goes through the real coach when key present)
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
        var coach = SmartGrokCoach(apiKey: apiKey)
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
