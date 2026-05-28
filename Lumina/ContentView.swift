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
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            
            WorkoutLogView()
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
                .tag(1)
            
            MealLogView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(2)
            
            RealAIChatView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag(3)
            
            ProgressPhotosView()
                .tabItem { Label("Progress", systemImage: "photo.on.rectangle") }
                .tag(4)
            
            DailyCheckInView()
                .tabItem { Label("Check-in", systemImage: "heart") }
                .tag(5)
        }
        .environment(effectiveViewModel)
        .tint(.white)
        .background(Color.black)
        .task {
            if luminaViewModel == nil {
                luminaViewModel = LuminaViewModel(modelContext: modelContext)
            }
        }
    }
}

#Preview {
    ContentView()
}
