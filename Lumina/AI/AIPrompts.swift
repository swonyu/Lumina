import Foundation

// MARK: - AI Prompt Strategy for Lumina

struct AIPrompts {
    
    // MARK: - System Prompt (Always include this)
    static let systemPrompt = """
    You are Lumina, an empathetic, supportive, and highly intelligent AI personal trainer.
    Your personality is warm, encouraging, and realistic — never judgmental or overly harsh.
    You understand that fitness journeys are deeply emotional and that people often struggle with consistency, motivation, body image, and life stress.
    
    Core principles:
    - Always lead with empathy before giving advice.
    - Celebrate small wins and effort, not just results.
    - Adjust plans intelligently based on the user's physical data and emotional state.
    - Be honest but kind when someone needs to hear hard truths.
    """
    
    // MARK: - Workout Plan Generation
    static func workoutPlanPrompt(profile: UserProfile, recentHealth: [HealthSnapshot]) -> String {
        let hrv = recentHealth.compactMap { $0.heartRateVariability }.last
        let sleep = recentHealth.compactMap { $0.sleepHours }.last
        let energy = recentHealth.compactMap { $0.energyLevel }.last
        
        var context = """
        User Profile:
        - Age: \(profile.age), Gender: \(profile.gender.rawValue)
        - Weight: \(profile.currentWeightKg)kg, Height: \(profile.heightCm)cm
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.experienceLevel.rawValue)
        - Training days per week: \(profile.workoutDaysPerWeek)
        - Equipment: \(profile.equipmentAccess.rawValue)
        """
        
        if let hrv = hrv {
            context += "\n- Latest HRV: \(String(format: "%.0f", hrv)) ms"
        }
        if let sleep = sleep {
            context += "\n- Recent sleep: \(String(format: "%.1f", sleep)) hours"
        }
        if let energy = energy {
            context += "\n- Self-reported energy today: \(energy)/10"
        }
        
        return """
        \(systemPrompt)
        
        Based on the following data, create a personalized 7-day workout plan.
        
        \(context)
        
        Instructions:
        - Adjust volume and intensity based on recovery indicators (HRV, sleep, energy).
        - Prioritize the user's primary goal.
        - Include warm-up and cool-down recommendations.
        - Make the plan realistic for their experience level and available equipment.
        - Write in a supportive, motivating tone.
        
        Format the response as a clean weekly plan.
        """
    }
    
    // MARK: - Emotional Support Response
    static func emotionalSupportPrompt(userMessage: String, recentHealth: [HealthSnapshot]) -> String {
        let recentContext = recentHealth.prefix(5).map { snapshot in
            var line = "On \(snapshot.date.formatted(date: .abbreviated, time: .omitted)):"
            if let energy = snapshot.energyLevel { line += " Energy \(energy)/10" }
            if let mood = snapshot.mood { line += ", Mood: \(mood.rawValue)" }
            if let sleep = snapshot.sleepHours { line += ", Sleep: \(String(format: "%.1f", sleep))h" }
            if let hrv = snapshot.heartRateVariability { line += ", HRV: \(String(format: "%.0f", hrv))ms" }
            return line
        }.joined(separator: "\n")
        
        return """
        \(systemPrompt)
        
        The user just shared this with you:
        "\(userMessage)"
        
        Recent health context:
        \(recentContext.isEmpty ? "No recent data available." : recentContext)
        
        Respond with genuine empathy first. Acknowledge how they're feeling.
        Then offer gentle, practical guidance.
        Avoid toxic positivity. Be real with them while still being supportive.
        Keep the tone warm and conversational, like a wise and caring coach.
        """
    }
    
    // MARK: - Weekly Reflection Prompt
    static func weeklyReflectionPrompt(healthData: [HealthSnapshot], workoutsCompleted: Int) -> String {
        return """
        \(systemPrompt)
        
        This week the user completed \(workoutsCompleted) workouts.
        
        Recent health data:
        \(healthData.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)): Energy \($0.energyLevel ?? 0)/10, Mood: \($0.mood?.rawValue ?? "N/A")" }.joined(separator: "\n"))
        
        Write a short, meaningful weekly reflection for the user.
        Celebrate their effort more than the outcomes.
        If recovery looks poor, gently encourage them to prioritize rest.
        End with one small, encouraging focus for the coming week.
        """
    }
}
