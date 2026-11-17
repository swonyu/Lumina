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
            .background(.regularMaterial)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Button
struct GlassButton: View {
    let title: String
    let action: () -> Void
    var isProminent: Bool = false

    // Opaque sRGB colors keep white headline text readable when system accent
    // colors become brighter in Dark Mode. The real UI contrast audit covers it.
    private static let prominentColors: [Color] = [
        Color(.sRGB, red: 31.0 / 255.0, green: 78.0 / 255.0, blue: 180.0 / 255.0, opacity: 1),
        Color(.sRGB, red: 99.0 / 255.0, green: 49.0 / 255.0, blue: 165.0 / 255.0, opacity: 1),
    ]

    init(title: String, isProminent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isProminent = isProminent
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    isProminent 
                    ? AnyShapeStyle(.linearGradient(colors: Self.prominentColors, startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(.regularMaterial)
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
    /// Lighter glass background for better performance (uses regularMaterial instead of ultraThin).
    /// Call `.glassBackground(ultraLight: true)` on the most expensive screens if you still want the heavier effect.
    func glassBackground(ultraLight: Bool = false) -> some View {
        if ultraLight {
            return AnyView(
                self
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.22))
            )
        } else {
            return AnyView(
                self
                    .background(.regularMaterial)
                    .background(Color.black.opacity(0.30))
            )
        }
    }
}
