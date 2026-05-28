import SwiftUI

struct AIChatView: View {
    @State private var messages: [ChatMessage] = [
        .init(role: .assistant, content: "Hey, I'm here. How are you really doing today?")
    ]
    @State private var inputText = ""
    @State private var isLoading = false
    
    // In real app, inject this
    private let grokService = GrokService(apiKey: ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? "")
    
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
                TextField("Talk to your coach...", text: $inputText)
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
        .navigationTitle("Your Coach")
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        messages.append(.init(role: .user, content: text))
        inputText = ""
        isLoading = true
        
        Task {
            do {
                // In real app, pass recent HealthSnapshots here
                let reply = try await grokService.getEmotionalSupport(
                    userMessage: text,
                    recentHealth: [] // TODO: Inject real data
                )
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
