import SwiftUI

struct GlassCelebrationBanner: View {
    let message: String
    
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("🎉")
                Text(message)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
        }
    }
}
