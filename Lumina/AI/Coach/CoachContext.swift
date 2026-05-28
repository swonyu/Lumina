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
            if let hrv = latest.heartRateVariability { text += "- HRV: \(Int(hrv))ms\n" }
            if let sleep = latest.sleepHours { text += "- Sleep: \(String(format: "%.1f", sleep)) hours\n" }
            if let energy = latest.energyLevel { text += "- Self-reported energy: \(energy)/10\n" }
            if let soreness = latest.sorenessLevel { text += "- Soreness: \(soreness)/10\n" }
        }
        
        if !recentCheckIns.isEmpty {
            let avgEnergy = recentCheckIns.compactMap { $0.energyLevel }.average ?? 0
            text += "Last 7-8 days average energy: \(String(format: "%.1f", avgEnergy))/10\n"
        }
        
        if !recentWorkouts.isEmpty {
            text += "Recent workouts logged: \(recentWorkouts.count) (latest: \(recentWorkouts.first?.workoutName ?? "unknown"))\n"
        }
        
        if !recentMeals.isEmpty {
            let totalProtein = recentMeals.compactMap { $0.protein }.reduce(0, +)
            text += "Recent meals: \(recentMeals.count) logged, ~\(Int(totalProtein))g protein tracked\n"
        }
        
        // NEW: Habits intelligence — coach can now reason about adherence, suggested habits, low streaks
        if !activeHabits.isEmpty {
            let streaks = activeHabits.compactMap { $0.currentStreak }
            let avgStreak = streaks.isEmpty ? 0 : Double(streaks.reduce(0, +)) / Double(streaks.count)
            let coachOnes = activeHabits.filter { $0.coachSuggested }.count
            text += "Active habits: \(activeHabits.count) (avg streak \(String(format: "%.0f", avgStreak)), \(coachOnes) coach-suggested)\n"
        }
        
        // NEW: High-signal recent AI analyses (progress photos, meals, weekly tasks, form) — this is what makes the coach dramatically smarter
        if !recentInsights.isEmpty {
            text += "Recent coach insights from photos/meals/habits/weekly: \n" + recentInsights.prefix(3).joined(separator: " | ").prefix(280) + "\n"
        }
        
        text += "Current streak: \(currentStreak) days\n"
        
        return text
    }
}

extension Collection where Element == Int {
    var average: Double? {
        guard !isEmpty else { return nil }
        return Double(reduce(0, +)) / Double(count)
    }
}
