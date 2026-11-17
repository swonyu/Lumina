import SwiftUI

struct RecoveryScoreCard: View {
    let snapshot: HealthSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot {
                Text(snapshot.date, style: .date)
                if let sleep = snapshot.sleepHours { Text(L("Recorded sleep: %.1f hours", sleep)) }
                if let hrv = snapshot.heartRateVariability { Text(L("Recorded HRV: %.0f ms", hrv)) }
                if let energy = snapshot.energyLevel { Text(L("Self-reported energy: %d/10", energy)) }
                if snapshot.sleepHours == nil && snapshot.heartRateVariability == nil && snapshot.energyLevel == nil {
                    Text(L("No sleep, HRV or energy measurement in this record."))
                }
            } else {
                Text(L("No health records available."))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
