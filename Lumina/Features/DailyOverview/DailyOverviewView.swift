import SwiftUI

struct DailyOverviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(L("daily_overview.title"))
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("daily_overview.readiness_label"))
                            .font(.headline)
                        HStack {
                            Text("84")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Spacer()
                            Text(L("daily_overview.excellent"))
                                .foregroundStyle(.green)
                        }
                        Text(L("daily_overview.readiness_message"))
                            .foregroundStyle(.secondary)
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("daily_overview.workout_label"))
                            .font(.headline)
                        Text(L("daily_overview.workout_details"))
                        GlassButton(title: L("daily_overview.start_session"), isProminent: true, action: {})
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("daily_overview.nutrition_label"))
                            .font(.headline)
                        Text(L("daily_overview.nutrition_details"))
                        GlassButton(title: L("daily_overview.log_meal"), action: {})
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("daily_overview.coach_note_label"))
                            .font(.headline)
                        Text(L("daily_overview.coach_note_message"))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("daily_overview.nav_title"))
        .withAppLanguage()
    }
}
