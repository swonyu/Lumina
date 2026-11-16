import SwiftUI

// MARK: - Agentic Coach Types (Round 8 improvements)
struct CoachAction: Identifiable {
    let id = UUID()
    let type: ActionType
    let parameters: [String: String]
    
    enum ActionType: String {
        case logCheckIn   = "LOG_CHECKIN"
        case logWorkout   = "LOG_WORKOUT"
        case savePlan     = "SAVE_PLAN"
        case logMeal      = "LOG_MEAL"           // New in Round 8
        case adjustGoal   = "ADJUST_GOAL"        // New in Round 8
        case reviewPlan   = "REVIEW_PLAN"        // Round 28: matches new autonomous Home recommendations
        case addHabit     = "ADD_HABIT"          // Round 42: direct coach-suggested habit addition
    }
}

struct RealAIChatView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    // Richer message model for Round 5 — supports per-message agentic actions
    struct DisplayedMessage: Identifiable {
        let id: UUID
        let base: ChatMessage
        var suggestedActions: [CoachAction] = []
        var actionFeedback: String? = nil   // e.g. "Logged ✓"
    }
    
    @State private var displayedMessages: [DisplayedMessage] = []
    
    private var initialMessage: String {
        if let name = viewModel.currentUser?.name {
            return "Hey \(name), I'm here. How are you feeling right now?"
        }
        return "Hey, I'm here. How are you feeling right now?"
    }
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showingInsights = false
    
    private var grokService: GrokService? {
        if let key = GrokService.configuredAPIKey {
            return GrokService(apiKey: key)
        }
        return nil
    }
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(displayedMessages) { dmsg in
                            VStack(alignment: .leading, spacing: 8) {
                                MessageBubble(message: dmsg.base)
                                    .id(dmsg.id)
                                
                                // Per-message agentic actions (Round 5 improvement)
                                if !dmsg.suggestedActions.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(dmsg.suggestedActions) { action in
                                            Button {
                                                executeActionOnMessage(action, for: dmsg.id)
                                            } label: {
                                                HStack {
                                                    Image(systemName: iconFor(action))
                                                    Text(titleFor(action))
                                                }
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(.blue.opacity(0.35))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.leading, 44)
                                }
                                
                                if let feedback = dmsg.actionFeedback {
                                    Text(feedback)
                                        .font(.caption2)
                                        .foregroundStyle(.green.opacity(0.8))
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        
                        if isLoading {
                            HStack {
                                Text(L("coach.thinking"))
                                    .font(.subheadline.italic())
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                Spacer(minLength: 44)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding()
                }
                .onChange(of: displayedMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(displayedMessages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            // Round 84/86: Proactive limited-impact awareness in chat (now uses cheap VM computed)
            if viewModel.hasLimitedCoachHabitImpact {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                    Text("Earlier coach notes mention habit effects. These are unverified notes, not measured outcomes.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
            
            HStack {
                TextField("Talk to your coach...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .opacity((inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading) ? 0.35 : 1.0)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()
            
            // Easy access to the new weekly AI reflection + deeper insights (opened as sheet for reliable navigation from tab)
            Button {
                showingInsights = true
            } label: {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Weekly Reflection & Insights")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .sheet(isPresented: $showingInsights) {
                CoachInsightsView()
            }
        }
        .glassBackground()
        .navigationTitle(L("coach.title"))
        .withAppLanguage()
        .drawingGroup() // Perf: chat with many coach action buttons + images can be expensive
        .onAppear {
            if displayedMessages.isEmpty {
                let initial = ChatMessage.assistant(initialMessage)
                displayedMessages = [DisplayedMessage(id: initial.id, base: initial)]
                
                if viewModel.hasLimitedCoachHabitImpact {
                    let note = ChatMessage.assistant("Earlier coach notes mention habit effects. Offline coaching cannot verify those claims; review the original records yourself.")
                    displayedMessages.append(DisplayedMessage(id: note.id, base: note))
                }
            }
            
            // Voice note integration - send pending transcript to coach
            if let pending = viewModel.pendingVoiceMessage, !pending.isEmpty {
                let voiceMsg = ChatMessage.user("🎤 \(pending)")
                displayedMessages.append(DisplayedMessage(id: voiceMsg.id, base: voiceMsg))
                viewModel.pendingVoiceMessage = nil
                
                // Automatically get coach response
                Task {
                    await sendMessageWithText(pending)
                }
            }
        }
        // Round 5 polish: Clear call-to-action when the smart/agentic coach is not yet unlocked
        .overlay(alignment: .topTrailing) {
            if GrokService.configuredAPIKey != nil {
                Text("✨ Grok")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.top, 8)
            } else {
                Text("Offline coaching")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.top, 8)
            }
        }
    }
    
    // Existing action execution logic (used by per-message buttons in Round 5)
    private func executeCoachAction(_ action: CoachAction) -> Bool {
        switch action.type {
        case .logCheckIn:
            let energy = Int(action.parameters["energy"] ?? "6") ?? 6
            let soreness = Int(action.parameters["soreness"] ?? "4") ?? 4
            let moodStr = action.parameters["mood"] ?? "good"
            let mood = Mood(rawValue: moodStr.capitalized) ?? .good
            let didTrain = (action.parameters["didTrain"] ?? "false").lowercased() == "true"
            
            viewModel.logQuickDailyCheckIn(
                energy: energy,
                soreness: soreness,
                sleepQuality: 7,
                stress: 4,
                mood: mood,
                didTrain: didTrain,
                note: "Logged via AI Coach"
            )
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User logged a check-in via coach suggestion (energy \(energy), soreness \(soreness))")
            
        case .logWorkout:
            let name = action.parameters["name"] ?? "Quick session from coach"
            let exertion = Int(action.parameters["exertion"] ?? action.parameters["perceivedExertion"] ?? "6")
            viewModel.logQuickWorkout(name: name, perceivedExertion: exertion, notes: "Suggested by Grok")
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User logged workout '\(name)' via coach suggestion")
            
        case .savePlan:
            if let plan = action.parameters["plan"] ?? action.parameters["content"] {
                viewModel.saveAIPlan(plan)
                viewModel.saveCoachMemoryEntry(type: .reflection, content: "User saved an AI-generated plan: \(plan.prefix(120))...")
            }
            
        case .logMeal:
            let mealName = action.parameters["mealName"] ?? action.parameters["name"] ?? "Coach-suggested meal"
            let calories = Double(action.parameters["calories"] ?? "0")
            let protein = Double(action.parameters["protein"] ?? "0")
            viewModel.logQuickMeal(name: mealName, calories: calories, protein: protein)
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User logged meal '\(mealName)' via coach action (\(Int(calories ?? 0)) cal, \(Int(protein ?? 0))g protein)")
            
            // Stronger follow-up for meal actions (uses the new rich context)
            Task { await viewModel.generatePostActionFollowUp(after: .logQuickWorkout, actionTitle: "Logged meal via coach") }
            
        case .addHabit:
            let habitName = action.parameters["name"] ?? action.parameters["habitName"] ?? "New habit from coach"
            let reason = action.parameters["reason"] ?? ""
            guard viewModel.addCoachSuggestedHabit(name: habitName,
                reason: reason.isEmpty ? nil : reason) else { return false }
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User added coach-suggested habit via chat: \(habitName)")
            let reply = ChatMessage.assistant("Habit saved: \(habitName). Use its completion button in Habits after you finish it.")
            displayedMessages.append(DisplayedMessage(id: reply.id, base: reply))
            return true
            
        case .adjustGoal:
            let goalType = action.parameters["goalType"] ?? action.parameters["type"] ?? "primary goal"
            let newTarget = action.parameters["newTarget"] ?? action.parameters["target"] ?? "a new target"
            let reason = action.parameters["reason"] ?? ""
            
            viewModel.applyGoalAdjustment(goalType: goalType, newTarget: newTarget, reason: reason)
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User accepted coach-suggested goal adjustment via chat: \(goalType) → \(newTarget)")
            
            // Round 29: Multi-turn follow-up (will appear on Home when user returns)
            Task { await viewModel.generatePostActionFollowUp(after: .adjustGoal, actionTitle: "Goal adjustment via chat") }
            
        case .reviewPlan:
            // Round 28: Execute the autonomous plan review action from chat (same power as Home)
            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User triggered coach-recommended plan review from chat")
            
            if let key = GrokService.configuredAPIKey, !key.isEmpty, let profile = viewModel.currentUser {
                Task {
                    let service = GrokService(apiKey: key)
                    if let plan = try? await service.generateSmartWorkoutPlan(profile: profile, context: viewModel.buildCoachContext()) {
                        await MainActor.run {
                            viewModel.lastGeneratedAIPlan = plan
                            viewModel.saveCoachMemoryEntry(type: .insight, content: "Coach generated updated plan after chat REVIEW_PLAN action")
                        }
                    }
                }
            }
            
            // Round 29: Multi-turn follow-up
            Task { await viewModel.generatePostActionFollowUp(after: .reviewPlan, actionTitle: "Plan review via chat") }
        }
        
        // Round 11: Generate a quick coach follow-up after the user took an action in chat
        Task {
            let apiKey = GrokService.configuredAPIKey ?? ""
            guard !apiKey.isEmpty else { return }
            
            let service = GrokService(apiKey: apiKey)
            let ctx = viewModel.buildCoachContext()
            let longTerm = !viewModel.smartMemorySummary.isEmpty ? viewModel.smartMemorySummary : viewModel.longTermCoachContext
            
            let followUpPrompt = "The user just completed the action: \(action.type.rawValue). Write one short, warm, natural follow-up sentence acknowledging what they did and offering a tiny next step or encouragement."
            
            if let followUp = try? await service.getSmartEmotionalSupport(
                userMessage: followUpPrompt,
                context: ctx,
                longTermMemory: longTerm
            ) {
                await MainActor.run {
                    let assistantMsg = ChatMessage.assistant(followUp.trimmingCharacters(in: .whitespacesAndNewlines))
                    displayedMessages.append(DisplayedMessage(id: assistantMsg.id, base: assistantMsg))
                }
            }
        }
        return true
    }
    
    private func iconFor(_ action: CoachAction) -> String {
        switch action.type {
        case .logCheckIn: return "heart.text.square"
        case .logWorkout: return "figure.strengthtraining.traditional"
        case .savePlan: return "doc.on.doc"
        case .logMeal: return "fork.knife"
        case .adjustGoal: return "slider.horizontal.3"
        case .reviewPlan: return "brain.head.profile"
        case .addHabit: return "list.bullet"
        }
    }
    
    private func titleFor(_ action: CoachAction) -> String {
        switch action.type {
        case .logCheckIn: return "Log this check-in"
        case .logWorkout: return "Log suggested workout"
        case .savePlan: return "Save this plan"
        case .logMeal: return "Log this meal"
        case .adjustGoal: return "Apply goal adjustment"
        case .reviewPlan: return "Review & update plan"
        case .addHabit: return "Add this habit"
        }
    }
    
    // Round 40 bug fix: restore missing helpers referenced by action buttons and voice notes
    private func executeActionOnMessage(_ action: CoachAction, for messageId: UUID) {
        guard executeCoachAction(action) else { return }
        // Mark the specific message's action as completed (simple UX)
        if let idx = displayedMessages.firstIndex(where: { $0.id == messageId }) {
            displayedMessages[idx].suggestedActions.removeAll { $0.id == action.id }
        }
    }
    
    private func sendMessageWithText(_ text: String) async {
        await MainActor.run {
            inputText = text
        }
        // Re-use the main send path
        sendMessage()
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        let userMsg = ChatMessage.user(text)
        displayedMessages.append(DisplayedMessage(id: userMsg.id, base: userMsg))
        
        inputText = ""
        isLoading = true
        
        Task {
            do {
                if GrokService.configuredAPIKey == nil {
                    let reply = try await GrokService().getSmartEmotionalSupport(
                        userMessage: text, context: viewModel.buildCoachContext())
                    let message = ChatMessage.assistant(reply)
                    displayedMessages.append(DisplayedMessage(id: message.id, base: message))
                    isLoading = false
                    return
                }
                // Round 18: Prefer the high-quality LLM-generated smart memory summary for best reasoning
                let richContext = viewModel.buildCoachContext()
                let longTermMemory = !viewModel.smartMemorySummary.isEmpty 
                    ? viewModel.smartMemorySummary 
                    : (viewModel.memorySummary.isEmpty ? viewModel.longTermCoachContext : viewModel.memorySummary)
                
                // Inject memory into the user message for strong referencing
                var enrichedMessage = longTermMemory.isEmpty ? text : "\(text)\n\n[Key things you know about my patterns and history: \(longTermMemory.prefix(850))]"
                
                // Round 87: Deeper agentic limited-impact intelligence — if user mentions habits/energy/photos/review/limited and we have known limited-impact coach habits, strongly bias the coach to proactively offer review/adjust using ACTION_SUGGESTION
                let lowerText = text.lowercased()
                if viewModel.hasLimitedCoachHabitImpact &&
                   (lowerText.contains("habit") || lowerText.contains("energy") || lowerText.contains("photo") || lowerText.contains("limited") || lowerText.contains("review") || lowerText.contains("adjust") || lowerText.contains("impact")) {
                    enrichedMessage += "\n\n[Important: You have previously detected limited measurable impact on one or more of your own coach-suggested habits via photo analysis and cross-signal data. If relevant to the user's message, proactively acknowledge it kindly and offer to review or adjust using ACTION_SUGGESTION:ADJUST_GOAL with goalType=\"coach-suggested habit\" and a clear reason referencing the limited impact. Prioritize this when the user talks about habits, energy, photos, or progress.]"
                }
                
                if let richReply = try? await grokService?.getSmartEmotionalSupport(
                    userMessage: enrichedMessage,
                    context: richContext,
                    longTermMemory: longTermMemory
                ) {
                    let (cleanReply, actions) = parseCoachActions(from: richReply)
                    
                    // Round 88: Guarantee review action for limited-impact cases — if we biased the prompt for limited context and no relevant action was produced, force one
                    var finalActions = actions
                    let limitedContextWasInjected = enrichedMessage.contains("limited measurable impact") || enrichedMessage.contains("limited-impact")
                    let hasReviewAction = finalActions.contains { $0.type == .adjustGoal || $0.type == .reviewPlan }
                    if limitedContextWasInjected && !hasReviewAction && viewModel.hasLimitedCoachHabitImpact {
                        let reviewAction = CoachAction(
                            type: .adjustGoal,
                            parameters: ["goalType": "coach-suggested habit", "reason": "Limited visible impact detected in photo analysis and cross-signal data"]
                        )
                        finalActions.append(reviewAction)
                    }
                    
                    let assistantBase = ChatMessage.assistant(cleanReply)
                    
                    await MainActor.run {
                        var newMsg = DisplayedMessage(id: assistantBase.id, base: assistantBase)
                        newMsg.suggestedActions = finalActions
                        displayedMessages.append(newMsg)
                        isLoading = false
                    }
                    return
                }
                
                // Legacy fallback
                let recentHealth = viewModel.getRecentHealthContextForAI()
                let reply = try await grokService?.getEmotionalSupport(
                    userMessage: text,
                    recentHealth: recentHealth,
                    profile: viewModel.currentUser
                ) ?? "I'm here with you."
                
                let assistantBase = ChatMessage.assistant(reply)
                await MainActor.run {
                    displayedMessages.append(DisplayedMessage(id: assistantBase.id, base: assistantBase))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    let fallback = viewModel.currentUser.map { "I'm here for your \($0.primaryGoal.rawValue.lowercased()) journey. Tell me more." } ?? "I'm here. Tell me more about what's going on."
                    let assistantBase = ChatMessage.assistant(fallback)
                    displayedMessages.append(DisplayedMessage(id: assistantBase.id, base: assistantBase))
                    isLoading = false
                }
            }
        }
    }
}

private func parseCoachActions(from reply: String) -> (cleanReply: String, actions: [CoachAction]) {
    var actions: [CoachAction] = []
    var clean = reply
    
    // Round 9: Support multiple ACTION_SUGGESTION lines for better agentic behavior
    let lines = reply.components(separatedBy: "\n")
    var cleanedLines: [String] = []
    
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased().hasPrefix("ACTION_SUGGESTION:") {
            let payload = trimmed.replacingOccurrences(of: "ACTION_SUGGESTION:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            
            let parts = payload.split(separator: "|").map { String($0) }
            guard let typeStr = parts.first else { continue }
            
            var params: [String: String] = [:]
            for p in parts.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map { String($0) }
                if kv.count == 2 {
                    params[kv[0]] = kv[1]
                }
            }
            
            if let type = CoachAction.ActionType(rawValue: typeStr.uppercased()) {
                actions.append(CoachAction(type: type, parameters: params))
            }
        } else {
            cleanedLines.append(line)
        }
    }
    
    clean = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    
    return (clean.isEmpty ? reply : clean, actions)
}
