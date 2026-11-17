import SwiftUI

struct AIChatView: View {
    @State private var messages: [ChatMessage] = [
        .init(role: .assistant, content: L("coach.initial_greeting", "there"))
    ]
    @State private var inputText = ""
    @State private var isLoading = false
    
    // In real app, inject this
    private let grokService = GrokService(apiKey: GrokService.configuredAPIKey ?? "")
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            HStack {
                TextField(L("coach.placeholder"), text: $inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("coach.title"))
        .withAppLanguage()
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        messages.append(.init(role: .user, content: text))
        inputText = ""
        isLoading = true
        
        Task {
            do {
                // Smart coach (rich context when we have the environment; graceful fallback inside)
                let context = CoachContext(
                    profile: nil,
                    recentHealth: [],
                    recentCheckIns: [],
                    recentWorkouts: [],
                    recentMeals: [],
                    activeHabits: [],
                    recentInsights: [],
                    currentStreak: 0
                )
                let reply = try await grokService.getSmartEmotionalSupport(userMessage: text, context: context)
                await MainActor.run {
                    messages.append(.init(role: .assistant, content: reply))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(.init(role: .assistant, content: "I'm here with you. Want to tell me more about what's going on?"))
                    isLoading = false
                }
            }
        }
    }
}
