import Foundation

struct SmartGrokCoach {
    private var conversationHistory: [ChatMessage] = []

    init(apiKey: String = "") { }

    mutating func respondToUser(message: String, context: CoachContext) async throws -> String {
        let reply = makeSupportReply(for: message, context: context)
        conversationHistory.append(.user(message))
        conversationHistory.append(.assistant(reply))
        return reply
    }

    func generateSmartWorkoutPlan(profile: UserProfile, context: CoachContext) async throws -> String {
        "Today should match your \(profile.experienceLevel.rawValue.lowercased()) level and \(profile.primaryGoal.rawValue.lowercased()) goal. Start with a focused warm-up, complete your main strength work, then finish with easy conditioning if recovery feels good."
    }

    func generateWeeklyReflection(context: CoachContext, workoutsCompleted: Int, avgEnergy: Double) async throws -> String {
        "You completed \(workoutsCompleted) workouts with average energy around \(String(format: "%.1f", avgEnergy))/10. Keep the next week simple: protect sleep, stay consistent, and increase volume only if recovery stays steady."
    }

    mutating func clearHistory() {
        conversationHistory.removeAll()
    }

    private func makeSupportReply(for message: String, context: CoachContext) -> String {
        let lowercasedMessage = message.lowercased()
        let goal = context.profile?.primaryGoal.rawValue.lowercased() ?? "your goals"

        if lowercasedMessage.contains("tired") || lowercasedMessage.contains("sleep") || lowercasedMessage.contains("exhausted") {
            return "If you feel tired, make recovery the priority today. Keep movement light, hydrate early, and treat sleep as the main workout tonight — it supports \(goal) long term."
        }

        if lowercasedMessage.contains("workout") || lowercasedMessage.contains("train") || lowercasedMessage.contains("gym") {
            return "For training today, aim for clean reps and controlled intensity toward \(goal). If your energy is below a 7/10, reduce volume before reducing consistency."
        }

        if lowercasedMessage.contains("food") || lowercasedMessage.contains("meal") || lowercasedMessage.contains("protein") {
            return "Keep nutrition simple: protein at each meal to fuel \(goal), colorful carbs around training, and enough water before you worry about perfect details."
        }

        if lowercasedMessage.contains("stuck") || lowercasedMessage.contains("motivation") || lowercasedMessage.contains("unmotivated") {
            return "When motivation is low, fall back to the smallest possible action that still moves \(goal) forward. Consistency beats intensity when you're in a dip."
        }

        if lowercasedMessage.contains("how am i") || lowercasedMessage.contains("progress") || lowercasedMessage.contains("doing") {
            let streakNote = context.currentStreak > 0 ? " You're on a \(context.currentStreak)-day streak — keep it going." : ""
            return "You're making real progress toward \(goal).\(streakNote) Focus on showing up consistently and the results will compound."
        }

        if !context.summary.isEmpty {
            let streakNote = context.currentStreak > 5 ? " (you're on a \(context.currentStreak)-day streak — nice work)" : ""
            return "I hear you. Based on your recent context and \(goal)\(streakNote), choose the smallest useful action today: one good meal, one focused workout block, or one recovery habit."
        }

        return "I hear you. Pick one small next step that supports your \(goal) today, then make it easy enough to actually do."
    }
}
