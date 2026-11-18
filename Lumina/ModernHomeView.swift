import SwiftUI
import SwiftData

struct ModernHomeView: View {
    @Binding var selectedTab: Int
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \DailyCheckIn.date, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(sort: \WorkoutLog.date, order: .reverse) private var workouts: [WorkoutLog]
    @Query(sort: \MealLog.date, order: .reverse) private var meals: [MealLog]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if UI_TESTING
                    if LuminaApp.isUIQA {
                        Text("Isolated QA store").font(.caption).accessibilityIdentifier("lumina.qa-store")
                    }
                    #endif
                    GroupBox(L("Your journal")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("Offline coaching"))
                            Text(L("Check-in streak: %d days", LuminaViewModel.checkInStreak(dates: checkIns.map(\.date))))
                            Text(L("Workouts logged today: %d", workouts.filter { Calendar.current.isDateInToday($0.date) }.count))
                            Text(L("Meals logged today: %d", meals.filter { Calendar.current.isDateInToday($0.date) }.count))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    GroupBox(L("Health records")) {
                        VStack(alignment: .leading, spacing: 12) {
                            RecoveryScoreCard(snapshot: viewModel.recentHealthSnapshots.first)
                            Text(L("Lumina does not calculate readiness, recovery or nutrition scores. These records do not establish a habit's effects."))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    GroupBox(L("Log and review")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(L("Log workout")) { selectedTab = 1 }
                            Button(L("Log meal")) { selectedTab = 2 }
                            NavigationLink(L("Daily check-in")) { DailyCheckInView() }
                            Button(L("Offline coach")) { selectedTab = 3 }
                            Button(L("Progress photos")) { selectedTab = 4 }
                            NavigationLink(L("Habits")) { HabitTrackerView() }
                            NavigationLink(L("Goals")) { GoalsView() }
                            NavigationLink(L("Journal")) { JournalView() }
                            NavigationLink(L("Training suggestions")) { AdaptivePlanView() }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .buttonStyle(HomeJournalActionStyle())
                        .controlSize(.large)
                    }
                    Text(L("Earlier prototype versions added sample records. Review existing entries before treating them as your own measurements."))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            // Keep journal content inside the navigation container's safe area.
            // The system bars remain separate; scrolling reveals the full records.
            .containerRelativeFrame(.vertical, alignment: .top)
            .clipped()
            .font(.body)
            .navigationTitle(L("Lumina"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Label(L("Settings"), systemImage: "gear") }
                        .accessibilityIdentifier("lumina.settings")
                }
            }
            .task { await viewModel.fetchRecentHealthData() }
        }
    }
}

// Opaque foreground/background keep every journal action legible independently
// of translucent system materials. Native button semantics and labels remain.
private struct HomeJournalActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
