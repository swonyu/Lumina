import Foundation

/// Compatibility name for the original local coach. All configurations use
/// deterministic on-device rules. The former paid HTTP client is retired.
/// The optional legacy argument is ignored; no credential is read or stored.
final class SmartGrokCoach {
    init(apiKey _: String = "") { }

    func respondToUser(message: String, context: CoachContext,
                       longTermMemory _: String = "") async throws -> String {
        try Task.checkCancellation()
        CoachMemory.shared.recordPattern("User said: \(message.prefix(80))...")
        return LocalCoachRules.reply(to: message, context: context, locale: Locale(identifier: "en"))
    }

    func generateSmartWorkoutPlan(profile: UserProfile, context: CoachContext) async throws -> String {
        try Task.checkCancellation()
        return LocalCoachRules.workoutOutline(locale: Locale(identifier: "en"))
    }

    func generateWeeklyReflection(context: CoachContext, workoutsCompleted: Int,
                                  avgEnergy: Double) async throws -> String {
        try Task.checkCancellation()
        // Older callers supplied guessed counts and a fixed energy average.
        // Describe only the actual saved records supplied in this context.
        let energies = context.recentCheckIns.compactMap(\.energyLevel).filter { (1...10).contains($0) }
        let energy = energies.average.map {
            "Average recorded energy: \(String(format: "%.1f", $0))/10 from \(energies.count) check-ins."
        } ?? "No valid recorded energy values are included."
        return "Local record reflection: \(context.recentWorkouts.count) workouts and \(context.recentCheckIns.count) check-ins are included. \(energy) Review their dates; these records may not all be from this week. They do not establish physical progress or a habit's effects."
    }

    // No model transcript is retained by this local compatibility service.
    func clearHistory() { }
}
