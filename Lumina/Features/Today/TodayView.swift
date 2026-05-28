import SwiftUI

struct TodayView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("today.title"))
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("today.readiness_label"))
                            .font(.title2.bold())
                        Text(L("today.readiness_message"))
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("today.workout_label"))
                            .font(.headline)
                        Text(L("today.workout_details"))
                        GlassButton(title: L("home.start_workout"), isProminent: true, action: {})
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("today.nutrition_label"))
                            .font(.headline)
                        HStack {
                            Text(L("today.protein_label"))
                            Spacer()
                            Text(L("today.calories_label"))
                        }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading) {
                        Text(L("today.coach_note_label"))
                            .font(.headline)
                        Text(L("today.coach_note_message"))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("today.nav_title"))
        .withAppLanguage()
    }
}
