import SwiftUI

struct StreakCalendarView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Consistency")
                    .font(.largeTitle.bold())
                
                GlassCard {
                    VStack {
                        Text("28 Day Streak")
                            .font(.title.bold())
                        Text("Personal Best")
                            .foregroundStyle(.green)
                    }
                }
                
                // Simple calendar grid placeholder
                VStack {
                    Text("This Month")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                        ForEach(1...30, id: \.self) { day in
                            Circle()
                                .fill(day % 3 == 0 ? Color.green : Color.white.opacity(0.1))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text("\(day)")
                                        .font(.caption2)
                                        .foregroundStyle(day % 3 == 0 ? .black : .white)
                                )
                        }
                    }
                }
                .padding()
                .glassBackground()
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Streak")
    }
}
