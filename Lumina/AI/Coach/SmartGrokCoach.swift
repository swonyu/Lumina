import Foundation

/// Real AI-powered coach using xAI Grok via direct OpenAI-compatible API.
/// Falls back to high-quality local rules when no API key or offline.
final class SmartGrokCoach {
    private let apiKey: String
    private var conversationHistory: [ChatMessage] = []

    init(apiKey: String = "") {
        self.apiKey = apiKey
    }

    func respondToUser(message: String, context: CoachContext, longTermMemory: String = "") async throws -> String {
        // Always record in local memory for patterns
        CoachMemory.shared.recordPattern("User said: \(message.prefix(80))...")

        guard !apiKey.isEmpty else {
            // High-quality fallback (kept for demo / no key)
            let reply = makeSupportReply(for: message, context: context)
            conversationHistory.append(ChatMessage.user(message))
            conversationHistory.append(ChatMessage.assistant(reply))
            return reply
        }

        // Build rich prompt using the excellent templates we already have (Round 10 improvement)
        let systemPrompt = SmartCoachPrompts.emotionalSupport(
            userMessage: message, 
            context: context, 
            longTermMemory: longTermMemory.isEmpty ? CoachMemory.shared.getRelevantContext() : longTermMemory
        )

        do {
            let reply = try await callXAIChat(
                systemPrompt: systemPrompt,
                userMessage: message,
                history: conversationHistory.suffix(6)
            )
            conversationHistory.append(ChatMessage.user(message))
            conversationHistory.append(ChatMessage.assistant(reply))
            // Store reflection for future context
            if message.count > 15 {
                CoachMemory.shared.addReflection("User: \(message.prefix(60)) → Coach: \(reply.prefix(80))")
            }
            return reply
        } catch {
            // Graceful fallback on network / rate / key error
            let fallback = makeSupportReply(for: message, context: context)
            conversationHistory.append(ChatMessage.user(message))
            conversationHistory.append(ChatMessage.assistant(fallback))
            return fallback
        }
    }

    func generateSmartWorkoutPlan(profile: UserProfile, context: CoachContext) async throws -> String {
        guard !apiKey.isEmpty else {
            return "Personalized plan for a \(profile.experienceLevel.rawValue.lowercased()) aiming for \(profile.primaryGoal.rawValue.lowercased()). Focus on 3-4 key lifts, 1-2 accessory movements, and 10-15 min mobility. Adjust volume based on how you feel tomorrow."
        }

        let prompt = SmartCoachPrompts.adaptiveWorkoutPrompt(
            profile: profile,
            context: context,
            recentPerformance: nil
        )
        return try await callXAIChat(systemPrompt: prompt, userMessage: "Generate the adaptive plan now.", history: [])
    }

    func generateWeeklyReflection(context: CoachContext, workoutsCompleted: Int, avgEnergy: Double) async throws -> String {
        guard !apiKey.isEmpty else {
            return "You completed \(workoutsCompleted) workouts with average energy around \(String(format: "%.1f", avgEnergy))/10. Keep the next week simple: protect sleep, stay consistent, and increase volume only if recovery stays steady."
        }

        let prompt = SmartCoachPrompts.weeklyReflection(
            context: context,
            workoutsCompleted: workoutsCompleted,
            avgEnergy: avgEnergy
        )
        return try await callXAIChat(systemPrompt: prompt, userMessage: "Write the weekly reflection.", history: [])
    }

    func clearHistory() {
        conversationHistory.removeAll()
    }

    // MARK: - Real xAI API call (OpenAI compatible endpoint)

    private func callXAIChat(systemPrompt: String, userMessage: String, history: [ChatMessage]) async throws -> String {
        guard !apiKey.isEmpty else { throw NSError(domain: "no-key", code: 0) }

        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 35

        var apiMessages: [XAIChatMessage] = []
        apiMessages.append(XAIChatMessage(role: "system", content: systemPrompt))

        // Add limited recent history (role mapping)
        for msg in history {
            let roleStr: String
            switch msg.role {
            case .user: roleStr = "user"
            case .assistant: roleStr = "assistant"
            case .system: roleStr = "system"
            }
            apiMessages.append(XAIChatMessage(role: roleStr, content: msg.content))
        }

        apiMessages.append(XAIChatMessage(role: "user", content: userMessage))

        let payload = XAIChatRequest(
            model: "grok-3-latest",
            messages: apiMessages,
            temperature: 0.75
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "xai", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "xAI error \(http.statusCode): \(body.prefix(200))"])
        }

        let decoded = try JSONDecoder().decode(XAIChatResponse.self, from: data)
        let content = decoded.choices?.first?.message?.content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let reply = content, !reply.isEmpty else {
            throw NSError(domain: "xai", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty reply from Grok"])
        }
        return reply
    }

    // MARK: - Fallback (excellent local rules, kept as offline / no-key path)

    private func makeSupportReply(for message: String, context: CoachContext) -> String {
        let lowercasedMessage = message.lowercased()
        let goal = context.profile?.primaryGoal.rawValue.lowercased() ?? "your goals"

        if lowercasedMessage.contains("tired") || lowercasedMessage.contains("sleep") || lowercasedMessage.contains("exhausted") {
            return "If you feel tired, make recovery the priority today. Keep movement light, hydrate early, and treat sleep as the main workout tonight — it supports \(goal) long term."
        }

        if lowercasedMessage.contains("workout") || lowercasedMessage.contains("train") || lowercasedMessage.contains("gym") {
            return "For training today, aim for clean reps and controlled intensity toward \(goal). If your energy is below a 7/10, reduce volume before reducing consistency."
        }

        if lowercasedMessage.contains("food") || lowercasedMessage.contains("meal") || lowercasedMessage.contains("protein") {
            return "Keep nutrition simple: protein at each meal to fuel \(goal), colorful carbs around training, and enough water before you worry about perfect details."
        }

        if lowercasedMessage.contains("stuck") || lowercasedMessage.contains("motivation") || lowercasedMessage.contains("unmotivated") {
            return "When motivation is low, fall back to the smallest possible action that still moves \(goal) forward. Consistency beats intensity when you're in a dip."
        }

        if lowercasedMessage.contains("how am i") || lowercasedMessage.contains("progress") || lowercasedMessage.contains("doing") {
            let streakNote = context.currentStreak > 0 ? " You're on a \(context.currentStreak)-day streak — keep it going." : ""
            return "You're making real progress toward \(goal).\(streakNote) Focus on showing up consistently and the results will compound."
        }

        if !context.summary.isEmpty {
            let streakNote = context.currentStreak > 5 ? " (you're on a \(context.currentStreak)-day streak — nice work)" : ""
            return "I hear you. Based on your recent context and \(goal)\(streakNote), choose the smallest useful action today: one good meal, one focused workout block, or one recovery habit."
        }

        return "I hear you. Pick one small next step that supports your \(goal) today, then make it easy enough to actually do."
    }
}

// MARK: - Minimal xAI API types (no external dependency)

private struct XAIChatRequest: Codable {
    let model: String
    let messages: [XAIChatMessage]
    let temperature: Double?
}

private struct XAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct XAIChatResponse: Codable {
    let choices: [XAIChoice]?
}

private struct XAIChoice: Codable {
    let message: XAIChatMessage?
}
