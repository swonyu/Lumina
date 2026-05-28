import Foundation
import SwiftData
import PhotosUI

@Model
final class ProgressPhoto {
    var id: UUID = UUID()
    var date: Date = Date()
    var photoData: Data?
    var weightAtTime: Double?
    var notes: String?

    init(date: Date = Date(), photoData: Data? = nil, weightAtTime: Double? = nil, notes: String? = nil) {
        self.date = date
        self.photoData = photoData
        self.weightAtTime = weightAtTime
        self.notes = notes
    }
}
