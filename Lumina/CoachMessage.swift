import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case system
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
            }

            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(14)
                .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 44)
            }
        }
    }

    private var backgroundStyle: Color {
        switch message.role {
        case .user:
            .blue
        case .assistant:
            .white.opacity(0.12)
        case .system:
            .purple.opacity(0.35)
        }
    }
}

struct CoachMessage: Identifiable {
    enum Role {
        case coach
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
}

struct CoachMessageBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            Text(message.text)
                .padding(14)
                .background(message.role == .user ? Color.blue.opacity(0.9) : Color.white.opacity(0.1))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .coach {
                Spacer()
            }
        }
    }
}
