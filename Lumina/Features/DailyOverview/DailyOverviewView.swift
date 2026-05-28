import SwiftUI

struct DailyOverviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Today at a Glance")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Readiness")
                            .font(.headline)
                        HStack {
                            Text("84")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Spacer()
                            Text("Excellent")
                                .foregroundStyle(.green)
                        }
                        Text("Your HRV and sleep look great. Go after it today.")
                            .foregroundStyle(.secondary)
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workout")
                            .font(.headline)
                        Text("Push + Core • 50 min")
                        GlassButton(title: "Start Session", isProminent: true) {}
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nutrition")
                            .font(.headline)
                        Text("1,240 / 2,450 cal • 98g protein")
                        GlassButton(title: "Log Meal") {}
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coach Note")
                            .font(.headline)
                        Text("You've been crushing it this week. One more solid day and you're at a new streak record.")
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Today")
    }
}
