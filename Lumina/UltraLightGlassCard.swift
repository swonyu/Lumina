import SwiftUI

/// Ultra-light glass card for maximum performance
/// Uses fewer layers than standard GlassCard
struct UltraLightGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 18
    
    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)   // Slightly cheaper than ultraThin
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
