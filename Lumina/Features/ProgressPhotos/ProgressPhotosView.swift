import SwiftUI
import PhotosUI
import SwiftData

struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var showAddedFeedback = false
    @State private var photoToDelete: ProgressPhoto?
    @State private var selectedPhotoPreview: SavedProgressPhotoPreview?
    @State private var photoImport = LocalPhotoImport()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("progress.transformation_title"))
                    .font(.largeTitle.bold())
                
                GlassButton(title: L("progress.add_photo_button"), action: {
                    showingPicker = true
                })
                .accessibilityIdentifier("lumina.progress.add-photo")

                if photoImport.isLoading {
                    ProgressView(L("Importing selected photo…"))
                }
                if let error = photoImport.errorMessage {
                    Text(L(error)).foregroundStyle(.primary)
                        .accessibilityIdentifier("lumina.progress.photo-error")
                }
                if let data = photoImport.data {
                    Button(L("Retry saving imported photo")) { saveImportedPhoto(data) }
                }
                if selectedItem != nil {
                    Button(L("Cancel selected photo")) {
                        selectedItem = nil
                        photoImport.clear()
                    }
                }
                
                // Round 61 + 62: Coach habit outcome nudge — tappable to trigger real photo capture for the coach's recommended habit
                if viewModel.proactiveRecommendationCategory == "habit" && !viewModel.proactiveCoachRecommendation.isEmpty {
                    let lower = viewModel.proactiveCoachRecommendation.lowercased()
                    if lower.contains("win") || lower.contains("delivering") || lower.contains("early") || lower.contains("photo") {
                        Button {
                            viewModel.coachWantsProgressPhotoForHabit = true
                            showingPicker = true
                            viewModel.saveCoachMemoryEntry(type: .pattern, content: "User tapped coach nudge in Progress Photos for habit outcome capture")
                        } label: {
                            GlassCard {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.yellow)
                                    Text(L("Saved suggestion: %@. Add a photo for your own records; photos do not measure a habit’s effects.", String(viewModel.proactiveCoachRecommendation.prefix(80))))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                
                if photos.isEmpty {
                    Text(L("progress.empty_state"))
                        .accessibilityIdentifier("lumina.progress.empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                if showAddedFeedback {
                    Text(L("progress.added_feedback"))
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
                
                if photos.count >= 2, let oldestPhoto = photos.last, let newestPhoto = photos.first {
                    Text(L("progress.compare_title"))
                        .font(.headline)
                    
                    HStack {
                        photoButton(oldestPhoto, location: "comparison.earliest")
                        photoButton(newestPhoto, location: "comparison.latest")
                    }
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(photos) { photo in
                        photoButton(photo, location: "history")
                            .contextMenu {
                                Button(role: .destructive) {
                                    photoToDelete = photo
                                } label: {
                                    Label(L("progress.delete_photo"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("tab.progress"))
        .withAppLanguage()
        .photosPicker(isPresented: $showingPicker, selection: $selectedItem, matching: .images)
        .sheet(item: $selectedPhotoPreview) { preview in
            SavedProgressPhotoDetail(preview: preview)
        }
        .onAppear {
            // Round 63 + 64: If coach requested a photo for a habit outcome, open the picker.
            // We intentionally do NOT clear the flag here — we keep it so the save handler can record special memory.
            if viewModel.coachWantsProgressPhotoForHabit {
                showingPicker = true
            }
        }
        .onChange(of: showingPicker) { _, isPresented in
            // Round 64 hygiene: If user dismisses the picker without taking a photo while coach was requesting one, clear the flag
            if !isPresented && viewModel.coachWantsProgressPhotoForHabit {
                viewModel.coachWantsProgressPhotoForHabit = false
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else {
                photoImport.clear()
                return
            }
            showAddedFeedback = false
            let generation = viewModel.dataRevision
            photoImport.load(using: { try await newItem.loadTransferable(type: Data.self) },
                isCurrentSession: { generation == 0 && viewModel.dataRevision == generation },
                onLoaded: { saveImportedPhoto($0) })
        }
        .onDisappear { photoImport.cancelPending() }
        .onChange(of: viewModel.dataRevision) { _, _ in
            selectedPhotoPreview = nil
            selectedItem = nil
            photoImport.clear()
        }
        .confirmationDialog(L("Delete this saved photo?"), isPresented: Binding(
            get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } }), titleVisibility: .visible) {
                Button(L("Delete photo"), role: .destructive) {
                    if let photo = photoToDelete { deletePhoto(photo) }
                    photoToDelete = nil
                }
                Button(L("Cancel"), role: .cancel) { photoToDelete = nil }
        } message: { Text(L("This cannot be undone. The original in your Photos library is not deleted.")) }
    }

    private func photoButton(_ photo: ProgressPhoto, location: String) -> some View {
        Button {
            selectedPhotoPreview = SavedProgressPhotoPreview(
                id: photo.id, date: photo.date, data: photo.photoData,
                notes: photo.notes, weight: photo.weightAtTime)
        } label: {
            PhotoThumbnail(photo: photo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Open progress photo from %@", photo.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(LocalizationManager.shared.currentLanguage.locale))))
        .accessibilityHint(L("Shows the complete saved image and its recorded details."))
        .accessibilityIdentifier("lumina.progress.\(location).\(photo.id.uuidString)")
    }

    private func saveImportedPhoto(_ data: Data) {
        guard viewModel.saveRecord(ProgressPhoto(photoData: data)) else { return }
        showAddedFeedback = true
        viewModel.coachWantsProgressPhotoForHabit = false
        viewModel.pendingCoachPhotoAnalysis = false
        selectedItem = nil
        photoImport.clear()
    }

    private func deletePhoto(_ photo: ProgressPhoto) {
        do {
            try modelContext.save()
            try modelContext.transaction { modelContext.delete(photo) }
        } catch { viewModel.errorMessage = L("Could not delete photo: %@", error.localizedDescription) }
    }
}

struct PhotoThumbnail: View {
    let photo: ProgressPhoto
    
    var body: some View {
        VStack {
            if let data = photo.photoData, let uiImage = UIImage(data: data) {
                // Downsample for better scrolling perf on many photos
                let displayImage = uiImage.preparingThumbnail(of: CGSize(width: 400, height: 400)) ?? uiImage
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .clipped()
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.2))
                    .frame(height: 160)
            }
            Text(photo.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(LocalizationManager.shared.currentLanguage.locale)))
                .font(.caption)
        }
    }
}


private struct SavedProgressPhotoPreview: Identifiable {
    let id: UUID
    let date: Date
    let data: Data?
    let notes: String?
    let weight: Double?
}

private struct SavedProgressPhotoDetail: View {
    @Environment(\.dismiss) private var dismiss
    let preview: SavedProgressPhotoPreview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(preview.date.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(LocalizationManager.shared.currentLanguage.locale)))
                        .font(.headline)
                        .accessibilityIdentifier("lumina.progress.detail.date")
                    if let data = preview.data, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(L("Saved progress photo"))
                            .accessibilityIdentifier("lumina.progress.detail.image")
                    } else {
                        ContentUnavailableView(L("Saved image unavailable"), systemImage: "photo",
                            description: Text(L("This record does not contain a readable saved image. Its other details remain available below.")))
                            .accessibilityIdentifier("lumina.progress.detail.image-unavailable")
                    }
                    if let notes = preview.notes, !notes.isEmpty {
                        Text(L("Saved notes")).font(.headline)
                        Text(notes)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("lumina.progress.detail.notes")
                    }
                    if let weight = preview.weight {
                        Text(L("Saved weight value")).font(.headline)
                        if weight.isFinite {
                            Text(weight.formatted())
                        } else {
                            Text(L("This saved value is not a finite number."))
                        }
                        Text(L("The earlier record does not include a weight unit."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Progress photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                        .accessibilityIdentifier("lumina.progress.detail.done")
                }
            }
        }
    }
}
