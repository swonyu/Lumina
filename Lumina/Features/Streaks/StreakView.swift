import SwiftUI

struct StreakView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(L("streak.consistency_title"))
                .font(.largeTitle.bold())
            
            GlassCard {
                HStack {
                    VStack {
                        Text("12")
                            .font(.system(size: 48, weight: .bold))
                        Text(L("streak.day_streak"))
                    }
                    Spacer()
                    Text("🔥")
                        .font(.system(size: 60))
                }
            }
            
            GlassCard {
                Text(L("streak.longest", 28))
            }
        }
        .padding()
        .glassBackground()
        .withAppLanguage()
    }
}
