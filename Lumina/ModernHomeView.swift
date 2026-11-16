import SwiftUI
import SwiftData

struct ModernHomeView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workouts: [WorkoutLog]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        #if UI_TESTING
                        if LuminaApp.isUIQA {
                            Text("Isolated QA store").font(.caption).accessibilityIdentifier("lumina.qa-store")
                        }
                        #endif
                        GroupBox("Your journal") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Offline coaching")
                                Text("Check-in streak: \(LuminaViewModel.checkInStreak(dates: checkIns.map(\.date))) days")
                                Text("Workouts logged today: \(workouts.filter { Calendar.current.isDateInToday($0.date) }.count)")
                                Text("Meals logged today: \(meals.filter { Calendar.current.isDateInToday($0.date) }.count)")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        GroupBox("Health records") {
                            VStack(alignment: .leading, spacing: 12) {
                                RecoveryScoreCard(snapshot: viewModel.recentHealthSnapshots.first)
                                Text("Lumina does not calculate readiness, recovery or nutrition scores. These records do not establish a habit's effects.")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        GroupBox("Log and review") {
                            VStack(alignment: .leading, spacing: 8) {
                                NavigationLink("Log workout") { WorkoutLogView() }
                                NavigationLink("Log meal") { MealLogView() }
                                NavigationLink("Daily check-in") { DailyCheckInView() }
                                NavigationLink("Offline coach") { RealAIChatView() }
                                NavigationLink("Progress photos") { ProgressPhotosView() }
                                NavigationLink("Habits") { HabitTrackerView() }
                                NavigationLink("Goals") { GoalsView() }
                                NavigationLink("Journal") { JournalView() }
                                NavigationLink("Training suggestions") { AdaptivePlanView() }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        Text("Earlier prototype versions added sample records. Review existing entries before treating them as your own measurements.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
                .clipped()
            }
            .font(.body)
            .navigationTitle("Lumina")
            .toolbar {
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gear") }
                    .accessibilityIdentifier("lumina.settings")
            }
            .task { await viewModel.fetchRecentHealthData() }
        }
    }
}
