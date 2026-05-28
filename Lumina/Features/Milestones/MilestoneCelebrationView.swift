import SwiftUI

struct MilestoneCelebrationView: View {
    let milestone: Milestone
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("🎉")
                .font(.system(size: 80))
            
            Text(milestone.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            
            Text(milestone.detail)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            GlassButton(title: "Thank you", isProminent: true, action: {
                dismiss()
            })
            .padding(.top)
        }
        .padding(40)
        .glassBackground()
    }
}
