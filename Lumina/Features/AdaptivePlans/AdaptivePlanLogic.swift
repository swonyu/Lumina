import Foundation

struct AdaptivePlanLogic {
    static func shouldAdjustPlan(recentCheckIns: [DailyCheckIn], recentSnapshots: [HealthSnapshot]) -> String? {
        let lowEnergyDays = recentCheckIns.filter { $0.energyLevel < 4 }.count
        let poorSleep = recentSnapshots.compactMap { $0.sleepHours }.filter { $0 < 6 }.count
        let lowHRV = recentSnapshots.compactMap { $0.heartRateVariability }.filter { $0 < 45 }.count
        
        if lowEnergyDays >= 3 || poorSleep >= 2 || lowHRV >= 2 {
            var observations: [String] = []
            if lowEnergyDays >= 3 { observations.append("energy ratings below 4/10") }
            if poorSleep >= 2 { observations.append("sleep entries below 6 hours") }
            if lowHRV >= 2 { observations.append("HRV entries below 45 ms") }
            return "Saved records include \(observations.joined(separator: " and ")). These records do not establish your current readiness. Review their dates and your situation before changing your training."
        }
        
        if recentCheckIns.filter({ $0.energyLevel > 7 }).count >= 4 {
            return "Some saved check-ins contain higher energy ratings. These ratings alone do not establish readiness for harder training."
        }
        
        return nil
    }
}
