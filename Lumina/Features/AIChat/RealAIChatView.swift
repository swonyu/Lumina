import SwiftUI

struct RealAIChatView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase

    private struct DisplayedMessage: Identifiable {
        let base: ChatMessage
        let source: CoachReplySource
        var id: UUID { base.id }
    }

    @State private var displayedMessages: [DisplayedMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showingInsights = false
    @State private var coach = Self.makeCoach()
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var availability: CoachModelAvailability = .unavailable(.modelNotReady)
    @State private var language = LocalizationManager.shared.currentLanguage

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(availability == .available ? L("coach.ai.available") : L("coach.ai.offline"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("lumina.coach.availability")
                Text(availabilityExplanation)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(displayedMessages) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                MessageBubble(message: item.base)
                                if item.base.role == .assistant {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sourceLabel(item.source))
                                            .accessibilityIdentifier("lumina.coach.reply-source")
                                        if let explanation = sourceExplanation(item.source) {
                                            Text(explanation)
                                                .accessibilityIdentifier("lumina.coach.reply-source-detail")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 14)
                                }
                            }
                            .id(item.id)
                        }
                        if isLoading {
                            HStack {
                                ProgressView().tint(.white)
                                Text(L("coach.thinking"))
                                    .font(.subheadline)
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
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

            if viewModel.hasLimitedCoachHabitImpact {
                Text(L("coach.ai.unverified_notes"))
                    .font(.caption)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                TextField(L("coach.ai.message_placeholder"), text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { sendMessage() }
                    .accessibilityLabel(L("Coach message"))
                    .accessibilityIdentifier("lumina.coach.message")
                if isLoading {
                    Button { stopRequest(announce: true) } label: {
                        Image(systemName: "stop.circle")
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(L("coach.ai.stop"))
                    .accessibilityIdentifier("lumina.coach.stop")
                }
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .frame(minWidth: 44, minHeight: 44)
                        .opacity(canSend ? 1 : 0.35)
                }
                .accessibilityLabel(L("Send message"))
                .accessibilityIdentifier("lumina.coach.send")
                .disabled(!canSend)
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Button { showingInsights = true } label: {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text(L("coach.ai.reflection"))
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lumina.coach.insights")
            .padding(.horizontal)
            .padding(.bottom, 8)
            .sheet(isPresented: $showingInsights) {
                NavigationStack {
                    CoachInsightsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("coach.ai.done")) { showingInsights = false }
                                    .accessibilityIdentifier("lumina.coach.insights.done")
                            }
                        }
                }
            }
        }
        .glassBackground()
        .navigationTitle(L("coach.title"))
        .withAppLanguage()
        .onAppear {
            refreshAvailability()
            if displayedMessages.isEmpty {
                let welcome = viewModel.currentUser.map { L("coach.ai.welcome_named", $0.name) }
                    ?? L("coach.ai.welcome")
                displayedMessages.append(DisplayedMessage(base: .assistant(welcome), source: .appNotice))
            }
            if let pending = viewModel.pendingVoiceMessage, !pending.isEmpty {
                viewModel.pendingVoiceMessage = nil
                inputText = pending
                sendMessage()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAvailability() }
            else { stopRequest(announce: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            stopRequest(announce: false)
            refreshAvailability()
        }
        .onDisappear { stopRequest(announce: false) }
    }

    private static func makeCoach() -> OnDeviceCoach {
        #if UI_TESTING
        // The existing UI acceptance cases exercise the offline reply contract
        // in the isolated QA store. Never invoke a real model from that run.
        // Release uses the real availability-checked generator; its generated
        // answer quality remains a separate physical-device acceptance gate.
        return OnDeviceCoach(generator: UIQAOfflineCoachGenerator())
        #else
        return OnDeviceCoach()
        #endif
    }

    private var canSend: Bool {
        !isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availabilityExplanation: String {
        switch availability {
        case .available: return L("coach.ai.available_detail")
        case .unavailable(let reason): return unavailableExplanation(reason)
        }
    }

    private func unavailableExplanation(_ reason: CoachUnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return L("coach.ai.device_unavailable")
        case .intelligenceNotEnabled: return L("coach.ai.disabled")
        case .modelNotReady: return L("coach.ai.not_ready")
        case .unsupportedLanguage: return L("coach.ai.language_unavailable")
        case .unavailable: return L("coach.ai.unavailable")
        }
    }

    private func sourceLabel(_ source: CoachReplySource) -> String {
        switch source {
        case .appleIntelligence: return L("coach.ai.source_model")
        case .appNotice: return "Lumina"
        case .offlineRules: return L("coach.ai.source_rules")
        }
    }

    private func sourceExplanation(_ source: CoachReplySource) -> String? {
        guard case .offlineRules(let reason) = source else { return nil }
        switch reason {
        case .unavailable(let why): return unavailableExplanation(why)
        case .messageTooLong: return L("coach.ai.message_long")
        case .contextLimit: return L("coach.ai.context_limit")
        case .rateLimited: return L("coach.ai.busy")
        case .inProgress: return L("coach.ai.still_stopping")
        case .timedOut: return L("coach.ai.timeout")
        case .failed: return L("coach.ai.failed")
        }
    }

    private func refreshAvailability() {
        language = LocalizationManager.shared.currentLanguage
        availability = coach.availability(for: language.locale)
    }

    private func sendMessage() {
        guard canSend else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = displayedMessages.compactMap { item -> CoachConversationTurn? in
            if item.base.role == .user {
                return CoachConversationTurn(role: .user, text: item.base.content)
            }
            guard item.base.role == .assistant, item.source != .appNotice else { return nil }
            return CoachConversationTurn(role: .assistant, text: item.base.content)
        }
        displayedMessages.append(DisplayedMessage(base: .user(text), source: .appNotice))
        inputText = ""
        isLoading = true
        let id = UUID()
        requestID = id
        let context = viewModel.buildCoachContext()
        let locale = language.locale
        requestTask = Task {
            defer {
                if requestID == id {
                    requestID = nil
                    requestTask = nil
                    isLoading = false
                    refreshAvailability()
                }
            }
            do {
                let reply = try await coach.reply(to: text, context: context,
                    history: history, locale: locale)
                guard !Task.isCancelled, requestID == id else { return }
                displayedMessages.append(DisplayedMessage(base: .assistant(reply.text), source: reply.source))
            } catch is CancellationError {
                // Stop, navigation, backgrounding and language changes discard
                // the pending response; they never manufacture another reply.
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                displayedMessages.append(DisplayedMessage(base: .assistant(L("coach.ai.try_again")),
                    source: .appNotice))
            }
        }
    }

    private func stopRequest(announce: Bool) {
        guard requestID != nil else { return }
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        if announce {
            displayedMessages.append(DisplayedMessage(base: .assistant(L("coach.ai.stopped")),
                source: .appNotice))
        }
    }
}

#if UI_TESTING
@MainActor
private struct UIQAOfflineCoachGenerator: OnDeviceCoachGenerating {
    func availability(for locale: Locale) -> CoachModelAvailability { .unavailable(.unavailable) }
    func generate(_ request: CoachModelRequest) async throws -> String {
        throw CoachGenerationFailure.unavailable(.unavailable)
    }
}
#endif
