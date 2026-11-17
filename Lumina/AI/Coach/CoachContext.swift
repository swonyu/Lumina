import Foundation

struct CoachContext {
    let profile: UserProfile?
    let recentHealth: [HealthSnapshot]
    let recentCheckIns: [DailyCheckIn]
    let recentWorkouts: [WorkoutLog]
    let recentMeals: [MealLog]
    let activeHabits: [Habit]      // NEW: feeds coach intelligence on behavior & streaks
    let recentInsights: [String]   // NEW: photo/meal/form/weekly analyses from memory — coach now references real visual + nutrition + habit data
    let currentStreak: Int
    
    var summary: String {
        var text = ""
        
        if let profile = profile {
            text += "User: \(profile.name), \(profile.age)y, Goal: \(profile.primaryGoal.rawValue), Level: \(profile.experienceLevel.rawValue)\n"
        }
        
        if let latest = recentHealth.first {
            text += "Latest Health Snapshot:\n"
            if let hrv = latest.heartRateVariability {
                text += "- HRV: \(Self.recordedNumber(hrv)) ms\n"
            }
            if let sleep = latest.sleepHours {
                text += "- Sleep: \(Self.recordedNumber(sleep)) hours\n"
            }
            if let energy = latest.energyLevel { text += "- Self-reported energy: \(energy)/10\n" }
            if let soreness = latest.sorenessLevel { text += "- Soreness: \(soreness)/10\n" }
        }
        
        if !recentCheckIns.isEmpty {
            let avgEnergy = recentCheckIns.compactMap { $0.energyLevel }.average ?? 0
            text += "Saved check-ins in this context: \(recentCheckIns.count); average energy: \(String(format: "%.1f", avgEnergy))/10\n"
        }
        
        if !recentWorkouts.isEmpty {
            text += "Recent workouts logged: \(recentWorkouts.count) (latest: \(recentWorkouts.first?.workoutName ?? "unknown"))\n"
        }
        
        if !recentMeals.isEmpty {
            let proteinValues = recentMeals.compactMap { $0.protein }
            text += "Saved meals in this context: \(recentMeals.count); \(proteinValues.count) with recorded protein. "
            if proteinValues.isEmpty {
                text += "Protein not recorded.\n"
            } else if proteinValues.contains(where: { !$0.isFinite || $0 < 0 }) {
                text += "Protein total unavailable: an invalid saved value needs review.\n"
            } else {
                let totalProtein = proteinValues.reduce(0, +)
                if totalProtein.isFinite {
                    text += "Total recorded protein: \(Self.recordedNumber(totalProtein)) g.\n"
                } else {
                    text += "Protein total unavailable: saved values exceed the numeric range.\n"
                }
            }
        }
        
        // NEW: Habits intelligence — coach can now reason about adherence, suggested habits, low streaks
        if !activeHabits.isEmpty {
            let avgStreak = activeHabits.map(\.currentStreak).average ?? 0
            let coachOnes = activeHabits.filter { $0.coachSuggested }.count
            text += "Active habits in this context: \(activeHabits.count) (avg streak \(String(format: "%.0f", avgStreak)), \(coachOnes) coach-suggested)\n"
        }
        
        // NEW: High-signal recent AI analyses (progress photos, meals, weekly tasks, form) — this is what makes the coach dramatically smarter
        if !recentInsights.isEmpty {
            text += "Recent coach insights from photos/meals/habits/weekly: \n" + recentInsights.prefix(3).joined(separator: " | ").prefix(280) + "\n"
        }
        
        text += "Current streak: \(currentStreak) days\n"
        
        return text
    }

    /// Saved editable values can exceed Int even while they remain finite.
    /// Keep large values readable without converting them to an integer or
    /// changing the record. Invalid legacy measurements remain explicit.
    private static func recordedNumber(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "unavailable (invalid saved value)" }
        // Keep the scientific exponent stable across Foundation implementations.
        return String(format: "%.6g", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: "E", with: "e")
    }
}

extension Collection where Element == Int {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0.0) { $0 + Double($1) } / Double(count)
    }
}
