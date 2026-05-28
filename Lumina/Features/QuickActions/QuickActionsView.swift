import SwiftUI

struct QuickActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                GlassButton(title: "Log Workout") {}
                GlassButton(title: "Log Meal") {}
                GlassButton(title: "Check-in") {}
            }
            
            HStack(spacing: 12) {
                GlassButton(title: "Add Photo") {}
                GlassButton(title: "Talk to Coach") {}
            }
        }
        .padding(.horizontal)
    }
}
