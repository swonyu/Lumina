import Foundation

/// Local image prompt helper that does not require an external SDK.
struct EmotionalImageGenerator {
    let apiKey: String

    func generateMotivationalImage(basePrompt: String, recentHealth: [HealthSnapshot]) async throws -> String {
        let avgEnergy = recentHealth.compactMap { $0.energyLevel }.average ?? 5
        let avgSleep = recentHealth.compactMap { $0.sleepHours }.average ?? 7

        var emotionalTone = "motivational and empowering"
        if avgEnergy < 4 {
            emotionalTone = "calm, gentle, and supportive"
        } else if avgEnergy > 7 && avgSleep > 7 {
            emotionalTone = "energetic, powerful, and inspiring"
        }

        let enhancedPrompt = "\(basePrompt), \(emotionalTone), cinematic lighting, premium fitness photography aesthetic"
        return "local-prompt://\(enhancedPrompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? enhancedPrompt)"
    }
}

extension Collection where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
