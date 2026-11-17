import SwiftUI

struct RecoveryScoreCard: View {
    let snapshot: HealthSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot {
                Text(snapshot.date, style: .date)
                if let sleep = snapshot.sleepHours { Text("Recorded sleep: \(sleep, specifier: "%.1f") hours") }
                if let hrv = snapshot.heartRateVariability { Text("Recorded HRV: \(hrv, specifier: "%.0f") ms") }
                if let energy = snapshot.energyLevel { Text("Self-reported energy: \(energy)/10") }
                if snapshot.sleepHours == nil && snapshot.heartRateVariability == nil && snapshot.energyLevel == nil {
                    Text("No sleep, HRV or energy measurement in this record.")
                }
            } else {
                Text("No health records available.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
