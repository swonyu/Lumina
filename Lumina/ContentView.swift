import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var luminaViewModel: LuminaViewModel?
    
    var body: some View {
        // Show the main UI as early as possible for fast perceived launch.
        // The old full black loading state has been removed so it no longer feels "stuck".
        TabView(selection: $selectedTab) {
            // Performance optimization: Only instantiate the selected tab.
            // This is one of the biggest sources of lag in apps with many complex tabs.
            Group {
                switch selectedTab {
                case 0: ModernHomeView()
                case 1: WorkoutLogView()
                case 2: MealLogView()
                case 3: RealAIChatView()
                case 4: ProgressPhotosView()
                case 5: DailyCheckInView()
                default: ModernHomeView()
                }
            }
            .tabItem { Label(L(tabTitle(for: selectedTab)), systemImage: tabIcon(for: selectedTab)) }
            .tag(selectedTab)
        }
        .environment(luminaViewModel ?? createTemporaryViewModel())
        .tint(.white)
        .background(Color.black)
        .withAppLanguage()
        .onChange(of: luminaViewModel?.coachWantsProgressPhotoForHabit) { _, wantsPhoto in
            if wantsPhoto == true {
                selectedTab = 4
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != 4 && luminaViewModel?.coachWantsProgressPhotoForHabit == true {
                luminaViewModel?.coachWantsProgressPhotoForHabit = false
            }
        }
        .onChange(of: luminaViewModel?.requestedTab) { _, requested in
            if let tab = requested {
                selectedTab = tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    luminaViewModel?.requestedTab = nil
                }
            }
        }
        .task {
            if luminaViewModel == nil {
                let vm = LuminaViewModel(modelContext: modelContext)
                luminaViewModel = vm

                // Heavy work (HealthKit, notifications, Live Activity, data loading) happens in background
                // so the main UI appears quickly instead of blocking on a black screen.
                Task {
                    await vm.bootstrapAfterLaunch()
                    await vm.seedStartupServices()
                }
            }
        }
    }

    // Helpers for the lazy tab items (keeps tab bar correct while only creating selected content)
    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return L("tab.home")
        case 1: return L("tab.workouts")
        case 2: return L("tab.nutrition")
        case 3: return L("tab.coach")
        case 4: return L("tab.progress")
        case 5: return L("tab.checkin")
        default: return L("tab.home")
        }
    }

    private func tabIcon(for index: Int) -> String {
        switch index {
        case 0: return "house.fill"
        case 1: return "figure.strengthtraining.traditional"
        case 2: return "fork.knife"
        case 3: return "sparkles"
        case 4: return "photo.on.rectangle"
        case 5: return "heart"
        default: return "house.fill"
        }
    }

    // Temporary fallback only while the real VM is being created (rare after first launch)
    private func createTemporaryViewModel() -> LuminaViewModel {
        LuminaViewModel(modelContext: modelContext)
    }
}

#Preview {
    ContentView()
}
