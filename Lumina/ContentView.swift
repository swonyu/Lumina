import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var luminaViewModel: LuminaViewModel?
    
    private var effectiveViewModel: LuminaViewModel {
        if let luminaViewModel {
            return luminaViewModel
        }
        return LuminaViewModel(modelContext: modelContext)
    }
    
    var body: some View {
        // For development: limited tabs to reduce lag from loading many complex views
        TabView(selection: $selectedTab) {
            ModernHomeView()
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
            
            DailyCheckInView()
                .tabItem { Label(L("tab.checkin"), systemImage: "heart") }
                .tag(5)
        }
        .environment(effectiveViewModel)
        .tint(.white)
        .background(Color.black)
        .withAppLanguage()
        .onChange(of: effectiveViewModel.coachWantsProgressPhotoForHabit) { _, wantsPhoto in
            if wantsPhoto {
                // Round 63: When coach (from Daily Briefing or elsewhere) wants a progress photo for a habit outcome, take the user there automatically
                selectedTab = 4 // Progress tab
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Round 65 + 67 hygiene: Clear any pending coach photo request if the user manually switches away from the flow
            if newTab != 4 && effectiveViewModel.coachWantsProgressPhotoForHabit {
                effectiveViewModel.coachWantsProgressPhotoForHabit = false
            }
        }
        .onChange(of: effectiveViewModel.requestedTab) { _, requested in
            if let tab = requested {
                selectedTab = tab
                // Clear after acting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    effectiveViewModel.requestedTab = nil
                }
            }
        }
        .task {
            if luminaViewModel == nil {
                luminaViewModel = LuminaViewModel(modelContext: modelContext)
            }
            
            // Request permissions for a great experience
            await luminaViewModel?.requestHealthKitAccess()
            await luminaViewModel?.requestNotificationPermission()
            await luminaViewModel?.scheduleProactiveCoachNotifications()
            
            // Start rich Live Activity (Coach Focus Today) early so user sees coach on lock screen immediately
            await MainActor.run {
                luminaViewModel?.startCoachFocusLiveActivity()
            }
        }
    }
}

#Preview {
    ContentView()
}
