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
            ModernHomeView(selectedTab: $selectedTab)
                .tabItem { Label(L("tab.home"), systemImage: "house.fill") }
                .tag(0)
            WorkoutLogView()
                .tabItem { Label(L("tab.workouts"), systemImage: "figure.strengthtraining.traditional") }
                .tag(1)
            MealLogView()
                .tabItem { Label(L("tab.nutrition"), systemImage: "fork.knife") }
                .tag(2)
            RealAIChatView()
                .tabItem { Label(L("tab.coach"), systemImage: "sparkles") }
                .tag(3)
            ProgressPhotosView()
                .tabItem { Label(L("tab.progress"), systemImage: "photo.on.rectangle") }
                .tag(4)
        }
        .id(luminaViewModel?.sessionID)
        .environment(luminaViewModel ?? createTemporaryViewModel())
        .onChange(of: luminaViewModel?.dataRevision) { _, revision in
            guard revision != nil, revision != 0 else { return }
            selectedTab = 0
            let model = LuminaViewModel(modelContext: modelContext, weeklyReminders: LuminaApp.weeklyReminders)
            luminaViewModel = model
            Task { await model.bootstrapAfterLaunch() }
        }
        .alert(L("Lumina"), isPresented: Binding(
            get: { luminaViewModel?.errorMessage != nil },
            set: { if !$0 { luminaViewModel?.errorMessage = nil } })) {
                Button(L("OK")) { luminaViewModel?.errorMessage = nil }
        } message: { Text(L(luminaViewModel?.errorMessage ?? "")) }
        .preferredColorScheme(.dark)
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
                let vm = LuminaViewModel(modelContext: modelContext, weeklyReminders: LuminaApp.weeklyReminders)
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

    // Temporary fallback only while the real VM is being created (rare after first launch)
    private func createTemporaryViewModel() -> LuminaViewModel {
        LuminaViewModel(modelContext: modelContext, weeklyReminders: LuminaApp.weeklyReminders)
    }
}

#Preview {
    ContentView()
}
