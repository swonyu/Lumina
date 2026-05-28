import SwiftUI

struct QuickActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("home.quick_actions"))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                GlassButton(title: L("workout.log_title"), action: {})
                GlassButton(title: L("meal.log_title"), action: {})
                GlassButton(title: L("tab.checkin"), action: {})
            }
            
            HStack(spacing: 12) {
                GlassButton(title: L("progress.add_photo_button"), action: {})
                GlassButton(title: L("coach.title"), action: {})
            }
        }
        .padding(.horizontal)
        .withAppLanguage()
    }
}
