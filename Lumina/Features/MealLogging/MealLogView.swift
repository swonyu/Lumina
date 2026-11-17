import SwiftUI
import SwiftData
import PhotosUI

struct MealLogView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var mealName = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var showingSuccess = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    
    @Query(sort: \MealLog.date, order: .reverse) private var recentMeals: [MealLog]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(L("meal.log_title"))
                    .font(.largeTitle.bold())
                
                GlassCard {
                    TextField(L("meal.what_did_you_eat"), text: $mealName)
                        .textFieldStyle(.roundedBorder)
                    Stepper(L("meal.calories_label", Int(calories)), value: $calories, in: 0...2000, step: 10)
                    Stepper(L("meal.protein_label", Int(protein)), value: $protein, in: 0...200, step: 5)
                    
                    // Round 37: Meal photo logging with AI coach feedback
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            Image(systemName: selectedPhotoData != nil ? "photo.fill" : "photo")
                            Text(selectedPhotoData != nil ? "Photo selected (tap to change)" : "Add meal photo (optional)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                selectedPhotoData = data
                            }
                        }
                    }
                    
                    if let data = selectedPhotoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                GlassButton(title: L("meal.save_button"), isProminent: true, action: {
                    saveMeal()
                })
                
                if recentMeals.isEmpty {
                    Text(L("meal.empty_state"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)
                } else {
                    GlassCard {
                        Text(L("meal.recent_label"))
                            .font(.headline)
                        ForEach(recentMeals.prefix(3)) { meal in
                            HStack {
                                Text(meal.mealName)
                                Spacer()
                                if let cals = meal.calories {
                                    Text("\(Int(cals)) cal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if meal.photoData != nil {
                                    Image(systemName: "photo")
                                        .font(.caption)
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.nutrition"))
        .withAppLanguage()
        .alert(L("meal.logged_alert_title"), isPresented: $showingSuccess) {
            Button(L("general.ok")) { }
        }
    }
    
    private func saveMeal() {
        guard !mealName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let log = MealLog(mealName: mealName, calories: calories, protein: protein, photoData: selectedPhotoData)
        guard viewModel.saveRecord(log) else { return }
        
        // Round 37: Trigger coach feedback if photo was included
        if selectedPhotoData != nil {
            Task {
                await viewModel.analyzeMealPhoto(mealLog: log)
            }
        }
        
        mealName = ""
        calories = 0
        protein = 0
        selectedPhotoData = nil
        selectedPhotoItem = nil
        showingSuccess = true
    }
}
