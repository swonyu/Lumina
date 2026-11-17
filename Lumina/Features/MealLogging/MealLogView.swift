import SwiftUI
import SwiftData
import PhotosUI

struct MealLogView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @State private var mealName = ""
    private enum InputFocus: Hashable { case name, calories, protein }
    @FocusState private var focusedField: InputFocus?
    @State private var calories = ""
    @State private var protein = ""
    @State private var showingNutrition = false
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
                    VStack(alignment: .leading, spacing: 6) {
                        mealFieldLabel("meal.what_did_you_eat", identifier: "lumina.meal.new-name-label")
                        TextField(L("meal.what_did_you_eat"), text: $mealName,
                                  prompt: Text(L("Meal name")).foregroundColor(Color(uiColor: .label)))
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .modifier(MealEntryFieldAppearance())
                            .accessibilityLabel(L("meal.what_did_you_eat"))
                            .accessibilityIdentifier("lumina.meal.new-name")
                    }
                    DisclosureGroup(L("Your nutrition entries (optional)"), isExpanded: $showingNutrition) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                mealFieldLabel("Calories", identifier: "lumina.meal.new-calories-label")
                                TextField(L("Calories"), text: $calories,
                                          prompt: Text(L("Not recorded")).foregroundColor(Color(uiColor: .label)))
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .calories)
                                    .modifier(MealEntryFieldAppearance())
                                    .accessibilityLabel(L("Calories"))
                                    .accessibilityIdentifier("lumina.meal.new-calories")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                mealFieldLabel("Protein in grams", identifier: "lumina.meal.new-protein-label")
                                TextField(L("Protein in grams"), text: $protein,
                                          prompt: Text(L("Not recorded")).foregroundColor(Color(uiColor: .label)))
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .protein)
                                    .modifier(MealEntryFieldAppearance())
                                    .accessibilityLabel(L("Protein in grams"))
                                    .accessibilityIdentifier("lumina.meal.new-protein")
                            }
                            Text(L("Leave a field empty if it was not recorded. These are your entries; Lumina does not estimate them from the photo."))
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .label))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .systemBackground),
                                            in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.top, 8)
                    }
                    .disclosureGroupStyle(MealNutritionDisclosureStyle())
                    
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
                .accessibilityIdentifier("lumina.meal.new-save")
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
                                    Text(L("%@ cal", LocalRecordDraft.numberText(cals)))
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
        .keyboardDismissalBar(isFocused: focusedField != nil) {
            focusedField = nil
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
    
    private func mealFieldLabel(_ key: String, identifier: String) -> some View {
        Text(L(key))
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(uiColor: .label))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
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
        let recordedCalories: Double?
        let recordedProtein: Double?
        do {
            recordedCalories = try LocalRecordDraft.number(calories, field: "calories")
            recordedProtein = try LocalRecordDraft.number(protein, field: "protein")
        } catch {
            viewModel.errorMessage = error.localizedDescription
            return
        }
        let log = MealLog(mealName: cleanName, calories: recordedCalories,
                          protein: recordedProtein, photoData: photoImport.data)
        guard viewModel.saveRecord(log) else { return }
        
        // Round 37: Trigger coach feedback if photo was included
        if photoImport.data != nil {
            Task {
                await viewModel.analyzeMealPhoto(mealLog: log)
            }
        }
        
        mealName = ""
        calories = ""
        protein = ""
        showingNutrition = false
        focusedField = nil
        photoImport.clear()
        selectedPhotoItem = nil
        showingSuccess = true
    }
}

/// Scope the action identifier to the real button, never its editable content.
private struct MealNutritionDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.forward")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .foregroundStyle(Color(uiColor: .label))
                .background(Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(L(configuration.isExpanded ? "Expanded" : "Collapsed"))
            .accessibilityIdentifier("lumina.meal.nutrition")

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}


/// Keep input text and its explicit prompt readable over the glass card in
/// either system appearance. Labels stay separate from editable field values.
private struct MealEntryFieldAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(Color(uiColor: .label))
            .tint(Color(uiColor: .label))
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(uiColor: .secondaryLabel), lineWidth: 1)
            }
    }
}
