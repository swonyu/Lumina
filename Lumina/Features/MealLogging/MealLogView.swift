import SwiftUI
import SwiftData
import PhotosUI

struct MealLogView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var mealName = ""
    @FocusState private var mealNameFocused: Bool
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var showingSuccess = false
    @State private var showingHistory = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoImport = LocalPhotoImport()
    
    @Query(sort: \MealLog.date, order: .reverse) private var recentMeals: [MealLog]
    
    var body: some View {
        // PhotosPicker evaluates its label outside the main actor.
        // Capture display state, without relaxing photoImport isolation.
        let hasSelectedPhoto = photoImport.data != nil
        let photoPickerTitle = L(hasSelectedPhoto ? "Photo selected (tap to change)" : "Add meal photo (optional)")
        ScrollView {
            VStack(spacing: 20) {
                Text(L("meal.log_title"))
                    .font(.largeTitle.bold())
                Button(L("View all saved meals")) { showingHistory = true }
                    .accessibilityIdentifier("lumina.meal.history")
                
                GlassCard {
                    TextField(L("meal.what_did_you_eat"), text: $mealName)
                        .focused($mealNameFocused)
                        .submitLabel(.done)
                        .onSubmit { mealNameFocused = false }
                        .textFieldStyle(.roundedBorder)
                    Stepper(L("meal.calories_label", Int(calories)), value: $calories, in: 0...2000, step: 10)
                    Stepper(L("meal.protein_label", Int(protein)), value: $protein, in: 0...200, step: 5)
                    
                    // Round 37: Meal photo logging with AI coach feedback
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            Image(systemName: hasSelectedPhoto ? "photo.fill" : "photo")
                            Text(photoPickerTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        guard let newItem else {
                            photoImport.clear()
                            return
                        }
                        let generation = viewModel.dataRevision
                        photoImport.load(using: { try await newItem.loadTransferable(type: Data.self) },
                            isCurrentSession: { generation == 0 && viewModel.dataRevision == generation })
                    }

                    if photoImport.isLoading {
                        ProgressView(L("Loading selected photo…"))
                    }
                    if let error = photoImport.errorMessage {
                        Text(L(error)).foregroundStyle(.primary)
                            .accessibilityIdentifier("lumina.meal.photo-error")
                    }
                    if selectedPhotoItem != nil {
                        Button(L("Remove selected photo")) {
                            selectedPhotoItem = nil
                            photoImport.clear()
                        }
                    }
                    
                    if let data = photoImport.data, let uiImage = UIImage(data: data) {
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
                .disabled(photoImport.isLoading || (selectedPhotoItem != nil && photoImport.data == nil))
                
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
                                    Text(L("%@ cal", cals.formatted()))
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
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissalBar(isFocused: mealNameFocused) {
            mealNameFocused = false
        }
        .withAppLanguage()
        .sheet(isPresented: $showingHistory) {
            NavigationStack { MealHistoryView() }
        }
        .onDisappear { photoImport.cancelPending() }
        .onChange(of: viewModel.dataRevision) { _, _ in
            selectedPhotoItem = nil
            photoImport.clear()
        }
        .alert(L("meal.logged_alert_title"), isPresented: $showingSuccess) {
            Button(L("general.ok")) { }
        }
    }
    
    private func saveMeal() {
        guard !photoImport.isLoading, selectedPhotoItem == nil || photoImport.data != nil else {
            viewModel.errorMessage = L("Wait for the selected photo to load, or remove it before saving.")
            return
        }
        let cleanName = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            viewModel.errorMessage = L("Enter a meal name.")
            return
        }
        let log = MealLog(mealName: cleanName, calories: calories, protein: protein, photoData: photoImport.data)
        guard viewModel.saveRecord(log) else { return }
        
        // Round 37: Trigger coach feedback if photo was included
        if photoImport.data != nil {
            Task {
                await viewModel.analyzeMealPhoto(mealLog: log)
            }
        }
        
        mealName = ""
        calories = 0
        protein = 0
        photoImport.clear()
        selectedPhotoItem = nil
        showingSuccess = true
    }
}
