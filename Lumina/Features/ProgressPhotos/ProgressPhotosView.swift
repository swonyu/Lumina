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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("progress.transformation_title"))
                    .font(.largeTitle.bold())
                
                GlassButton(title: L("progress.add_photo_button"), action: {
                    showingPicker = true
                })
                
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
                                    Text("Coach: \(viewModel.proactiveCoachRecommendation.prefix(80)) — tap to capture photo for this habit.")
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
                        PhotoThumbnail(photo: oldestPhoto)
                        PhotoThumbnail(photo: newestPhoto)
                    }
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(photos) { photo in
                        PhotoThumbnail(photo: photo)
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
            .drawingGroup()   // Perf: reduce overdraw for image-heavy view
        }
        .glassBackground()
        .navigationTitle(L("tab.progress"))
        .withAppLanguage()
        .drawingGroup() // Round 17 perf (image heavy)
        .photosPicker(isPresented: $showingPicker, selection: $selectedItem, matching: .images)
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
            guard let newItem else { return }
            Task {
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                        viewModel.errorMessage = "Could not read the selected photo. Try another image."
                        return
                    }
                    guard viewModel.saveRecord(ProgressPhoto(photoData: data)) else { return }
                    showAddedFeedback = true
                    viewModel.coachWantsProgressPhotoForHabit = false
                    viewModel.pendingCoachPhotoAnalysis = false
                    selectedItem = nil
                } catch { viewModel.errorMessage = "Could not load photo: \(error.localizedDescription)" }
            }
        }
        .confirmationDialog("Delete this saved photo?", isPresented: Binding(
            get: { photoToDelete != nil }, set: { if !$0 { photoToDelete = nil } }), titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    if let photo = photoToDelete { deletePhoto(photo) }
                    photoToDelete = nil
                }
                Button("Cancel", role: .cancel) { photoToDelete = nil }
        } message: { Text("This cannot be undone. The original in your Photos library is not deleted.") }
    }

    private func deletePhoto(_ photo: ProgressPhoto) {
        do {
            try modelContext.save()
            try modelContext.transaction { modelContext.delete(photo) }
        } catch { viewModel.errorMessage = "Could not delete photo: \(error.localizedDescription)" }
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
            Text(photo.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
        }
    }
}
