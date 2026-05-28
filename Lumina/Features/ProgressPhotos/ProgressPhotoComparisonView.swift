import SwiftUI
import SwiftData

struct ProgressPhotoComparisonView: View {
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    
    var body: some View {
        ScrollView {
            if photos.count >= 2 {
                VStack(spacing: 24) {
                    Text("Compare Your Journey")
                        .font(.title.bold())
                    
                    HStack(spacing: 16) {
                        VStack {
                            if let first = photos.last, let data = first.photoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 220)
                                    .clipped()
                                    .cornerRadius(16)
                            }
                            Text(photos.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                                .font(.caption)
                        }
                        
                        VStack {
                            if let second = photos.first, let data = second.photoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 220)
                                    .clipped()
                                    .cornerRadius(16)
                            }
                            Text(photos.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                                .font(.caption)
                        }
                    }
                }
                .padding()
            } else {
                Text("Add at least two progress photos to compare")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .glassBackground()
    }
}
