import SwiftUI

/// Performance-optimized glass card
/// Reduces layer count compared to previous versions
struct OptimizedGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    
    init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // Helps reduce overdraw
            .compositingGroup()
    }
}
