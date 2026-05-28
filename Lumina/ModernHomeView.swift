import SwiftUI

struct ModernHomeView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    private var greetingName: String {
        viewModel.currentUser?.name ?? "there"
    }
    
    private var currentStreak: Int {
        // Simple demo streak based on recent check-ins (in real app would be smarter)
        min(viewModel.recentHealthSnapshots.count + 8, 14)
    }
    
    private var readinessValue: Int {
        viewModel.readinessValue
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {   // Reduced spacing for less work
                    // Greeting - kept light
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("home.good_morning", greetingName))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        Text(L("home.streak", currentStreak))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Readiness Rings - reduced size slightly for perf
                    HStack(spacing: 12) {
                        GlassProgressRing(progress: Double(readinessValue) / 100.0, size: 82, lineWidth: 7, color: .green, title: L("home.readiness"), valueText: "\(readinessValue)")
                        GlassProgressRing(progress: Double(viewModel.recoveryValue) / 100.0, size: 82, lineWidth: 7, color: .blue, title: L("home.recovery"), valueText: "\(viewModel.recoveryValue)")
                        GlassProgressRing(progress: Double(viewModel.nutritionValue) / 100.0, size: 82, lineWidth: 7, color: .orange, title: L("home.nutrition"), valueText: "\(viewModel.nutritionValue)")
                    }
                    .padding(.horizontal, 20)
                    
                    // AI Coach Insight - now proactive + powered by real Grok when key is set (Round 3)
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.yellow)
                                Text(L("home.coach_insight"))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                // Round 27 polish: visible "Grok powered" when real LLM is active
                                if !ProcessInfo.processInfo.environment["XAI_API_KEY", default: ""].isEmpty {
                                    Text("Grok")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.yellow.opacity(0.7))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.yellow.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                if viewModel.isGeneratingInsight {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Button {
                                        Task { await viewModel.refreshCoachInsight(force: true) }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Text(viewModel.currentCoachInsight)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                            
                            // Round 7: Proactive, contextual, one-tap coach suggestions directly on Home
                            if !viewModel.homeCoachSuggestions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(viewModel.homeCoachSuggestions) { suggestion in
                                        Button {
                                            if suggestion.actionType == .openCoachChat {
                                                // Navigation handled by parent or we can use a binding later
                                            } else {
                                                viewModel.triggerHomeCoachSuggestion(suggestion)
                                            }
                                        } label: {
                                            HStack {
                                                let lower = suggestion.title.lowercased()
                                                let icon = suggestion.actionType == .logCheckIn ? "heart.text.square" :
                                                           lower.contains("habit") || lower.contains("streak") ? "list.bullet" :
                                                           suggestion.actionType == .adjustGoal ? "slider.horizontal.3" :
                                                           suggestion.actionType == .reviewPlan ? "brain.head.profile" :
                                                           "figure.strengthtraining.traditional"
                                                Image(systemName: icon)
                                                Text(suggestion.title)
                                                Spacer()
                                            }
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(.white.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 6)
                            }
                            
                            // Round 28: Coach's Daily Briefing — now LLM-generated from the coach's smartMemorySummary for genuinely personalized, wise language
                            if !viewModel.coachDailyBriefing.isEmpty || viewModel.isGeneratingBriefing {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Coach's Daily Briefing")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.yellow.opacity(0.9))
                                        
                                        if !ProcessInfo.processInfo.environment["XAI_API_KEY", default: ""].isEmpty {
                                            Text("Grok")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.yellow.opacity(0.7))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(.yellow.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                        
                                        if viewModel.isGeneratingBriefing {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        }
                                    }
                                    
                                    Text(viewModel.coachDailyBriefing.isEmpty ? "Thinking..." : viewModel.coachDailyBriefing)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.78))
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    // Round 37 + 39 + 61: One-tap actions directly from Daily Briefing — now outcome-aware for coach habits (positive wins or measurement needs)
                                    HStack(spacing: 8) {
                                        Button {
                                            viewModel.logQuickDailyCheckIn(energy: 7, soreness: 4, sleepQuality: 7, stress: 4, mood: .good, didTrain: false)
                                            viewModel.followUpSuccessMessage = "Check-in logged. Thanks!"
                                        } label: {
                                            Text("Quick Check-in")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.white.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                        
                                        // Dynamic third capsule when we have a strong coach habit outcome signal (Round 61 + 64)
                                        if viewModel.proactiveRecommendationCategory == "habit" && !viewModel.proactiveCoachRecommendation.isEmpty {
                                            Button {
                                                if viewModel.isPositiveWinForBriefingCapsule {
                                                    // Positive win case — set real signal for photo capture + strong memory
                                                    viewModel.coachWantsProgressPhotoForHabit = true
                                                    viewModel.followUpSuccessMessage = "Great habit momentum! Ready to capture the win with a progress photo?"
                                                    viewModel.saveCoachMemoryEntry(type: .pattern, content: "User prompted toward progress photo after positive coach habit win from Daily Briefing")
                                                } else {
                                                    // Measurement / low streak case
                                                    viewModel.logQuickDailyCheckIn(energy: 6, soreness: 4, sleepQuality: 7, stress: 4, mood: .good, didTrain: false, note: "Habit check-in from Daily Briefing")
                                                    viewModel.followUpSuccessMessage = "Habit check-in logged — photo soon to measure impact?"
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    if viewModel.shouldShowCameraInBriefingCapsule {
                                                        Image(systemName: "camera.fill")
                                                            .font(.caption2)
                                                    }
                                                    Text(viewModel.dynamicBriefingCapsuleTitle)
                                                }
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(viewModel.isPositiveCoachHabitWinCapsule ? .yellow.opacity(0.28) : .green.opacity(0.25))
                                                .overlay(
                                                    viewModel.isPositiveCoachHabitWinCapsule ?
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(.yellow.opacity(0.4), lineWidth: 1)
                                                    : nil
                                                )
                                                .clipShape(Capsule())
                                            }
                                        }
                                        
                                        Button {
                                            // Round 63 + 70 hygiene: clear coach photo signals when user takes a different major action
                                            if viewModel.coachWantsProgressPhotoForHabit {
                                                viewModel.coachWantsProgressPhotoForHabit = false
                                            }
                                            if viewModel.coachPhotoReflection != nil {
                                                viewModel.coachPhotoReflection = nil
                                            }
                                            
                                            // Prefer the live autonomous pattern rec if coach surfaced one (much smarter UX)
                                            if viewModel.showingProactiveRecommendation {
                                                let rec = viewModel.makeProactiveSuggestion()
                                                viewModel.triggerHomeCoachSuggestion(rec)
                                            } else if !viewModel.proactiveCoachRecommendation.isEmpty {
                                                // Fallback to whatever the coach last recommended
                                                let suggestion = LuminaViewModel.HomeCoachSuggestion(
                                                    title: viewModel.proactiveCoachRecommendation,
                                                    actionType: viewModel.proactiveRecommendationAction
                                                )
                                                viewModel.triggerHomeCoachSuggestion(suggestion)
                                            } else {
                                                viewModel.logQuickWorkout(name: "Coach-suggested session", perceivedExertion: 6, notes: "From daily briefing")
                                            }
                                        } label: {
                                            Text("Take Action")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.white.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .foregroundStyle(.white)
                                }
                                .padding(.top, 6)
                            }
                            
                            // Round 68 + 69 + 80: Dedicated Coach Reflection card after a coach-requested photo analysis (polish: consistent light material + Grok transparency when real analysis)
                            if let reflection = viewModel.coachPhotoReflection {
                                UltraLightGlassCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "sparkles")
                                                .foregroundStyle(.yellow)
                                            Text("Coach Reflection")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.yellow.opacity(0.9))
                                            
                                            if !ProcessInfo.processInfo.environment["XAI_API_KEY", default: ""].isEmpty {
                                                Text("Grok")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.yellow.opacity(0.7))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(.yellow.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(reflection)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.85))
                                        
                                        HStack(spacing: 12) {
                                            Button {
                                                viewModel.coachPhotoReflection = nil
                                                viewModel.requestedTab = 4 // Progress Photos tab
                                            } label: {
                                                Text("View photos")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(.white.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button {
                                                viewModel.coachPhotoReflection = nil
                                                viewModel.requestedTab = 3 // Coach chat tab
                                            } label: {
                                                Text("Discuss with coach")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 4)
                                                    .background(.yellow.opacity(0.25))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button {
                                                viewModel.coachPhotoReflection = nil
                                                if viewModel.requestedTab != nil {
                                                    viewModel.requestedTab = nil
                                                }
                                            } label: {
                                                Text("Later")
                                                    .font(.caption2)
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            // Round 27: Fresh AI-generated daily insight (makes the coach feel more autonomous)
                            if !viewModel.proactiveHomeInsight.isEmpty && !viewModel.isGeneratingInsight {
                                Text(viewModel.proactiveHomeInsight)
                                    .font(.caption.italic())
                                    .foregroundStyle(.white.opacity(0.68))
                                    .padding(.top, 2)
                            }
                            
                            // Round 29: Gentle "coach is learning you" state when memory is still building
                            if viewModel.smartMemorySummary.isEmpty && viewModel.memorySummary.isEmpty && !viewModel.isGeneratingInsight {
                                Text("The coach is still getting to know your patterns. Keep using the app — it gets much smarter with time.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.top, 4)
                            }
                            
                            // Round 27/28 + 60: Prominent autonomous pattern-driven recommendation from coach memory + transparency
                            if viewModel.showingProactiveRecommendation && !viewModel.proactiveCoachRecommendation.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: viewModel.proactiveRecIconName)
                                            .foregroundStyle(.yellow)
                                        Text(viewModel.proactiveCardHeaderLabel)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.yellow.opacity(0.95))
                                        
                                        // Round 61/88/89 polish: subtle celebration indicator for winning habits (uses pre-computed for hygiene)
                                        if viewModel.isWinningHabitRec {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                        }
                                        
                                        if !ProcessInfo.processInfo.environment["XAI_API_KEY", default: ""].isEmpty {
                                            Text("Grok")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.yellow.opacity(0.7))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 0)
                                                .background(.yellow.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                        
                                        // Round 28 polish: quick way to ask the coach to re-analyze memory
                                        Button {
                                            Task { await viewModel.generateProactiveCoachRecommendation() }
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text(viewModel.proactiveCoachRecommendation)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    // Round 80: Use pre-computed why text (perf: avoids repeated string work in view body)
                                    Text(viewModel.proactiveCardWhyText)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                        .padding(.bottom, 2)
                                    
                                    Button {
                                        let recSuggestion = viewModel.makeProactiveSuggestion()
                                        viewModel.triggerHomeCoachSuggestion(recSuggestion)
                                        viewModel.showingProactiveRecommendation = false
                                    } label: {
                                        HStack {
                                            Text(viewModel.proactiveRecActionButtonText)
                                                .font(.caption.weight(.semibold))
                                            Image(systemName: "arrow.right")
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.white.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(.regularMaterial)   // Perf: lighter than ultraThin for coach rec cards
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.top, 6)
                            }
                            
                            // Round 29: Multi-turn follow-up after user acted on an autonomous recommendation
                            // (The coach continues the conversation intelligently)
                            if viewModel.showingPostActionFollowUp && !viewModel.postActionCoachFollowUp.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "arrow.turn.down.right")
                                            .foregroundStyle(.purple.opacity(0.8))
                                        Text("Coach suggests next")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.purple.opacity(0.9))
                                    }
                                    
                                    Text(viewModel.postActionCoachFollowUp)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.9))
                                    
                                    HStack(spacing: 12) {
                                        Button {
                                            // Round 30: Actually execute the smart follow-up (generate plan, log session, etc.)
                                            viewModel.executePostActionFollowUp()
                                        } label: {
                                            if viewModel.isExecutingFollowUp {
                                                HStack(spacing: 4) {
                                                    ProgressView().scaleEffect(0.7)
                                                    Text("Working...")
                                                }
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                            } else {
                                                Text("Let's do it")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 5)
                                        .background(.purple.opacity(0.35))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .buttonStyle(.plain)
                                        .disabled(viewModel.isExecutingFollowUp)
                                        
                                        if !viewModel.isExecutingFollowUp {
                                            Button {
                                                viewModel.showingPostActionFollowUp = false
                                                viewModel.postActionCoachFollowUp = ""
                                                viewModel.postActionFollowUpAction = nil
                                            } label: {
                                                Text("Later")
                                                    .font(.caption)
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(.regularMaterial)   // Perf + polish consistency
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.top, 4)
                            }
                            
                            // Round 37: Brief success feedback + one-tap next action after coach suggestion
                            if !viewModel.followUpSuccessMessage.isEmpty && !viewModel.isExecutingFollowUp {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(viewModel.followUpSuccessMessage)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.9))
                                        Spacer()
                                        Button {
                                            viewModel.followUpSuccessMessage = ""
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.6))
                                        }
                                    }
                                    
                                    // One-tap next action
                                    Button {
                                        if viewModel.followUpSuccessPrefersPhotoCapture {
                                            // Round 58-60: strong outcome focus — log + push photo to document the win for the coach
                                            viewModel.logQuickDailyCheckIn(energy: 7, soreness: 4, sleepQuality: 7, stress: 4, mood: .good, didTrain: false, note: "Win logged for coach habit — capturing impact")
                                            viewModel.followUpSuccessMessage = "Win logged — a quick progress photo will let your coach see the real results."
                                        } else {
                                            viewModel.logQuickDailyCheckIn(energy: 7, soreness: 4, sleepQuality: 7, stress: 4, mood: .good, didTrain: false, note: "Follow-up after coach suggestion")
                                            viewModel.followUpSuccessMessage = "Great follow-through! Logged."
                                        }
                                    } label: {
                                        Text(viewModel.followUpSuccessPrefersPhotoCapture ? "Log win + capture with photo" : "Log quick check-in as next step")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(.green.opacity(0.3))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                .padding(8)
                                .background(.green.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.top, 4)
                            }
                            
                            NavigationLink(destination: RealAIChatView()) {
                                Text(L("home.talk_to_coach"))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .task {
                        // Round 27 + 58 + 62 + 68 hygiene: clear stale coach signals on fresh launch
                        if viewModel.justAddedCoachHabit != nil {
                            viewModel.justAddedCoachHabit = nil
                        }
                        if viewModel.coachWantsProgressPhotoForHabit {
                            viewModel.coachWantsProgressPhotoForHabit = false
                        }
                        if viewModel.coachPhotoReflection != nil {
                            viewModel.coachPhotoReflection = nil
                        }
                        if viewModel.pendingCoachPhotoAnalysis {
                            viewModel.pendingCoachPhotoAnalysis = false
                        }
                        
                        // Round 27: Maximum proactivity — the coach prepares its smartest thinking the moment the app opens
                        await viewModel.refreshCoachInsight()
                        
                        // Generate the highest quality memory summary first so everything below can use it
                        if viewModel.smartMemorySummary.isEmpty {
                            let summary = await viewModel.generateMemorySummaryWithAI()
                            await MainActor.run {
                                viewModel.smartMemorySummary = summary
                            }
                        }
                        
                        // Always regenerate a fresh proactive daily insight so the coach feels actively thinking for you on every launch
                        await viewModel.generateProactiveHomeInsight()
                        
                        // Generate contextual, memory-aware suggestions
                        await viewModel.generateHomeCoachSuggestionsWithAI(from: viewModel.buildCoachContext())
                        
                        // Round 27: Pattern-driven autonomous recommendation (goal/plan adjustment surfaced from smart memory)
                        await viewModel.generateProactiveCoachRecommendation()
                        
                        // Round 28: LLM-powered Daily Briefing — the most visible daily expression of the coach's intelligence
                        await viewModel.generateCoachDailyBriefing()
                    }
                    
                    // Today's Focus - lighter card
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L("home.todays_focus"))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(viewModel.todaysFocusDuration)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Text("\(viewModel.todaysFocusWorkout) • \(focusExercises(for: viewModel.currentUser?.primaryGoal))")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                            
                            NavigationLink(destination: WorkoutLogView()) {
                                Text(L("home.start_workout"))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Quick Actions - simplified
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("home.quick_actions"))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            NavigationLink(destination: DailyCheckInView()) {
                                Label(L("home.quick_checkin"), systemImage: "heart.text.square")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(destination: RealAIChatView()) {
                                Label(L("home.quick_coach"), systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // New: Direct access to the now-smart AI coach for plans
                        NavigationLink(destination: AdaptivePlanView()) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                Text("Get AI Training Plan from Grok")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(.purple.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.horizontal, 20)
                    }
                    
                    // Nutrition - very light
                    UltraLightGlassCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("home.nutrition_today"))
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Text(L("home.nutrition_status", viewModel.nutritionValue))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 50)
                .drawingGroup()   // ← Major performance win for the entire home content
            }
            .background(
                LinearGradient(
                    colors: [.black, Color.black.opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .withAppLanguage()
    }
    
    private func focusExercises(for goal: PrimaryGoal?) -> String {
        switch goal {
        case .buildMuscle: return "Bench, OHP, Dips"
        case .loseFat: return "Full body circuit + cardio"
        case .improveStrength: return "Heavy compounds (Squat, Deadlift, Press)"
        case .improveEndurance: return "Metcon + running intervals"
        default: return "Balanced strength + conditioning"
        }
    }
}
