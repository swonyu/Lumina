import Foundation

struct RecoveryScore {
    let score: Int          // 0-100
    let label: String
    let recommendation: String
    let color: String       // "green", "yellow", "red"
    
    static func calculate(from snapshot: HealthSnapshot) -> RecoveryScore {
        var score = 70
        
        if let hrv = snapshot.heartRateVariability {
            if hrv > 70 { score += 15 }
            else if hrv < 40 { score -= 20 }
        }
        
        if let sleep = snapshot.sleepHours {
            if sleep >= 8 { score += 10 }
            else if sleep < 6 { score -= 15 }
        }
        
        if let energy = snapshot.energyLevel {
            score += (energy - 5) * 3
        }
        
        if let soreness = snapshot.sorenessLevel {
            score -= (soreness - 3) * 4
        }
        
        score = max(0, min(100, score))
        
        let label: String
        let recommendation: String
        let color: String
        
        if score >= 75 {
            label = "Ready to Train"
            recommendation = "You're recovered. Go hard today."
            color = "green"
        } else if score >= 55 {
            label = "Moderate Recovery"
            recommendation = "Good day for moderate training or technique work."
            color = "yellow"
        } else {
            label = "Prioritize Recovery"
            recommendation = "Your body needs rest. Consider mobility or a full rest day."
            color = "red"
        }
        
        return RecoveryScore(score: score, label: label, recommendation: recommendation, color: color)
    }
}
