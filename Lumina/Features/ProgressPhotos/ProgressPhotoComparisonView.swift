import SwiftUI
import SwiftData

struct ProgressPhotoComparisonView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
    
    var body: some View {
        ScrollView {
            if photos.count >= 2 {
                VStack(spacing: 24) {
                    Text(L("progress.compare_journey_title"))
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
                Text(L("progress.compare_empty"))
                    .foregroundStyle(.secondary)
                    .padding()
            }

            // Round 37: AI Coach Photo Analysis
            if photos.count >= 2 {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.purple)
                            Text("Ask Coach for Insights")
                                .font(.headline)
                        }
                        
                        Text("Get personalized analysis on your progress, correlated with your training and recovery data between these dates.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                        
                        Button {
                            // Trigger AI analysis
                            Task {
                                // For demo, analyze first vs last photo dates
                                if let oldPhoto = photos.last, let newPhoto = photos.first {
                                    await viewModel.analyzeProgressPhotos(
                                        oldDate: oldPhoto.date,
                                        newDate: newPhoto.date
                                    )
                                }
                            }
                        } label: {
                            Text("Analyze My Progress with Coach")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding()
            }
        }
        .glassBackground()
        .withAppLanguage()
    }
}
