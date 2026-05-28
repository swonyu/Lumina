import Foundation

struct CoachContext {
    let profile: UserProfile?
    let recentHealth: [HealthSnapshot]
    let recentCheckIns: [DailyCheckIn]
    let recentWorkouts: [WorkoutLog]
    let recentMeals: [MealLog]
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
            text += "Last 7 days average energy: \(String(format: "%.1f", avgEnergy))/10\n"
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
