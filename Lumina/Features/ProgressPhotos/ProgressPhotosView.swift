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
                                    deletePhoto(photo)
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
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    let newPhoto = ProgressPhoto(photoData: data)
                    modelContext.insert(newPhoto)
                    try? modelContext.save()
                    
                    // Round 37: Auto-trigger stronger AI Progress Photo Analysis if there's a previous photo
                    if photos.count >= 1, let oldest = photos.last {
                        Task {
                            await viewModel.analyzeProgressPhotos(oldDate: oldest.date, newDate: newPhoto.date)
                        }
                    }
                    
                    await MainActor.run {
                        showAddedFeedback = true
                        // Auto-hide feedback after a short time
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            showAddedFeedback = false
                        }
                    }
                    
                    // Round 63 + 65 + 67 + 68: Stronger post-capture chaining for coach-requested habit photos
                    if viewModel.coachWantsProgressPhotoForHabit {
                        await viewModel.saveCoachMemoryEntry(
                            type: .insight, 
                            content: "Coach-requested progress photo captured for habit outcome tracking. This creates a strong visual record of the habit's impact."
                        )
                        await MainActor.run {
                            viewModel.coachWantsProgressPhotoForHabit = false
                            viewModel.followUpSuccessMessage = "Excellent — the coach will review this photo for your habit progress."
                            
                            // Round 68 + 71: Mark that the upcoming analysis is coach-driven so we can surface the real analysis text
                            viewModel.pendingCoachPhotoAnalysis = true
                            
                            // Trigger insight refresh (analysis will set the actual reflection text)
                            Task {
                                await viewModel.refreshCoachInsight()
                            }
                        }
                    }
                }
                // Clear selection to prevent re-triggering and allow adding more photos easily
                await MainActor.run {
                    selectedItem = nil
                }
            }
        }
    }
    
    private func deletePhoto(_ photo: ProgressPhoto) {
        modelContext.delete(photo)
        try? modelContext.save()
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
