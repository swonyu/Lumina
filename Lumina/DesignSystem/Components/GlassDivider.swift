import SwiftUI

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }
}
