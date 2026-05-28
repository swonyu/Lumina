import SwiftUI

struct GlassMotivationBanner: View {
    let message: String
    
    var body: some View {
        GlassCard(cornerRadius: 20) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
