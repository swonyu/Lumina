import SwiftUI

// MARK: - Glass Card (Core Component)
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    
    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Button
struct GlassButton: View {
    let title: String
    let action: () -> Void
    var isProminent: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isProminent ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    isProminent 
                    ? AnyShapeStyle(.linearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Background
extension View {
    func glassBackground() -> some View {
        self
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.25))
    }
}
