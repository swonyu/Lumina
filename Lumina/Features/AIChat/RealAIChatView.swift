import SwiftUI

struct RealAIChatView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    @State private var messages: [ChatMessage] = []
    
    private var initialMessage: String {
        if let name = viewModel.currentUser?.name {
            return "Hey \(name), I'm here. How are you feeling right now?"
        }
        return "Hey, I'm here. How are you feeling right now?"
    }
    @State private var inputText = ""
    @State private var isLoading = false
    
    private var grokService: GrokService? {
        if let key = ProcessInfo.processInfo.environment["XAI_API_KEY"] {
            return GrokService(apiKey: key)
        }
        return nil
    }
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isLoading {
                            HStack {
                                Text("Coach is thinking...")
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
                        .foregroundStyle(.white)
                        .opacity((inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading) ? 0.35 : 1.0)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Your Coach")
        .onAppear {
            if messages.isEmpty {
                messages = [.init(id: UUID(), role: .assistant, content: initialMessage)]
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        messages.append(.init(id: UUID(), role: .user, content: text))
        inputText = ""
        isLoading = true
        
        Task {
            do {
                let recentHealth = viewModel.getRecentHealthContextForAI()
                let reply = try await grokService?.getEmotionalSupport(
                    userMessage: text,
                    recentHealth: recentHealth,
                    profile: viewModel.currentUser
                ) ?? "I'm here with you."
                
                await MainActor.run {
                    messages.append(.init(id: UUID(), role: .assistant, content: reply))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    let fallback = viewModel.currentUser.map { "I'm here for your \($0.primaryGoal.rawValue.lowercased()) journey. Tell me more." } ?? "I'm here. Tell me more about what's going on."
                    messages.append(.init(id: UUID(), role: .assistant, content: fallback))
                    isLoading = false
                }
            }
        }
    }
}
