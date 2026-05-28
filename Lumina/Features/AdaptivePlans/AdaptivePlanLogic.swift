import Foundation

struct AdaptivePlanLogic {
    static func shouldAdjustPlan(recentCheckIns: [DailyCheckIn], recentSnapshots: [HealthSnapshot]) -> String? {
        let lowEnergyDays = recentCheckIns.filter { $0.energyLevel < 4 }.count
        let poorSleep = recentSnapshots.compactMap { $0.sleepHours }.filter { $0 < 6 }.count
        let lowHRV = recentSnapshots.compactMap { $0.heartRateVariability }.filter { $0 < 45 }.count
        
        if lowEnergyDays >= 3 || poorSleep >= 2 || lowHRV >= 2 {
            return "Your recovery has been low lately. I recommend reducing volume by 20-30% this week and focusing on quality movement."
        }
        
        if recentCheckIns.filter({ $0.energyLevel > 7 }).count >= 4 {
            return "You've been feeling strong. We can safely push a bit harder this week if you're up for it."
        }
        
        return nil
    }
}
