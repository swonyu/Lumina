import SwiftUI
import PhotosUI
import SwiftData

struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var showAddedFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Transformation")
                    .font(.largeTitle.bold())
                
                GlassButton(title: "+ Add Progress Photo") {
                    showingPicker = true
                }
                
                if photos.isEmpty {
                    Text("Take progress photos over time to see your transformation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                if showAddedFeedback {
                    Text("Photo added ✓")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
                
                if photos.count >= 2, let oldestPhoto = photos.last, let newestPhoto = photos.first {
                    Text("Compare")
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
                                    Label("Delete Photo", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Progress")
        .photosPicker(isPresented: $showingPicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    let newPhoto = ProgressPhoto(photoData: data)
                    modelContext.insert(newPhoto)
                    try? modelContext.save()
                    
                    await MainActor.run {
                        showAddedFeedback = true
                        // Auto-hide feedback after a short time
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            showAddedFeedback = false
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
                Image(uiImage: uiImage)
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
