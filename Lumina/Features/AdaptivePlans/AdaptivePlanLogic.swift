import Foundation
import SwiftData

struct AdaptivePlanLogic {
    static var checkInDescriptor: FetchDescriptor<DailyCheckIn> {
        var descriptor = FetchDescriptor<DailyCheckIn>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 14
        return descriptor
    }

    static var snapshotDescriptor: FetchDescriptor<HealthSnapshot> {
        var descriptor = FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 14
        return descriptor
    }

    static func shouldAdjustPlan(recentCheckIns: [DailyCheckIn], recentSnapshots: [HealthSnapshot]) -> String? {
        let lowEnergyDays = recentCheckIns.filter { $0.energyLevel < 4 }.count
        let poorSleep = recentSnapshots.compactMap { $0.sleepHours }.filter { $0 < 6 }.count
        let lowHRV = recentSnapshots.compactMap { $0.heartRateVariability }.filter { $0 < 45 }.count
        
        if lowEnergyDays >= 3 || poorSleep >= 2 || lowHRV >= 2 {
            var observations: [String] = []
            if lowEnergyDays >= 3 { observations.append(L("energy ratings below 4/10")) }
            if poorSleep >= 2 { observations.append(L("sleep entries below 6 hours")) }
            if lowHRV >= 2 { observations.append(L("HRV entries below 45 ms")) }
            return L("Saved records include %@. These records do not establish your current readiness. Review their dates and your situation before changing your training.", observations.joined(separator: L(" and ")))
        }
        
        if recentCheckIns.filter({ $0.energyLevel > 7 }).count >= 4 {
            return L("Some saved check-ins contain higher energy ratings. These ratings alone do not establish readiness for harder training.")
        }
        
        return nil
    }
}
