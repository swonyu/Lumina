import Foundation
import SwiftData
import Testing
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import CryptoKit
@testable import Lumina

@MainActor
struct PhotoImportIntegrityTests {
    @Test func laterSelectionWinsWhenEarlierLoaderFinishesLast() async throws {
        let importer = LocalPhotoImport()
        let earlier = ControlledPhotoLoader()
        let later = ControlledPhotoLoader()
        let earlierImage = try photo(1), laterImage = try photo(2)
        #expect(earlierImage != laterImage)
        var saved: [Data] = []
        let first = importer.load(using: { try await earlier.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await earlier.waitUntilStarted()
        let second = importer.load(using: { try await later.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await later.waitUntilStarted()
        later.finish(with: .success(laterImage))
        await second.value
        earlier.finish(with: .success(earlierImage))
        await first.value
        #expect(importer.data == laterImage)
        #expect(saved == [laterImage])
        #expect(!importer.isLoading && importer.errorMessage == nil)
    }

    @Test func canceledLoaderCannotRefillClearedMealDraft() async throws {
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
        let image = try photo(3)
        var saved: [Data] = []
        let pending = importer.load(using: { try await delayed.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await delayed.waitUntilStarted()
        importer.clear()
        delayed.finish(with: .success(image))
        await pending.value
        #expect(importer.data == nil && saved.isEmpty)
        #expect(!importer.isLoading && importer.errorMessage == nil)
    }

    @Test func leavingScreenCancelsPendingPhotoWithoutDiscardingCompletedPhoto() async throws {
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
        let lateImage = try photo(4), completedImage = try photo(5)
        var saved: [Data] = []
        let pending = importer.load(using: { try await delayed.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await delayed.waitUntilStarted()
        importer.cancelPending()
        delayed.finish(with: .success(lateImage))
        await pending.value
        #expect(importer.data == nil && saved.isEmpty && !importer.isLoading)
        #expect(importer.errorMessage != nil)
        let completed = importer.load(using: { completedImage }, isCurrentSession: { true })
        await completed.value
        importer.cancelPending()
        #expect(importer.data == completedImage && importer.errorMessage == nil)
    }

    @Test func deletionInvalidatesImportAndStaleModelWrites() async throws {
        let schema = Schema(LuminaApp.modelTypes)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let model = LuminaViewModel(modelContext: container.mainContext)
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
        let image = try photo(6)
        let generation = model.dataRevision
        var callbackInvoked = false
        let pending = importer.load(using: { try await delayed.load() },
            isCurrentSession: { model.dataRevision == generation && generation == 0 },
            onLoaded: { bytes in
                callbackInvoked = true
                model.saveRecord(ProgressPhoto(photoData: bytes))
            })
        await delayed.waitUntilStarted()
        try model.deleteAllLocalRecords()
        delayed.finish(with: .success(image))
        await pending.value
        #expect(!callbackInvoked && importer.data == nil && !importer.isLoading)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ProgressPhoto>()) == 0)
        #expect(!model.saveRecord(MealLog(mealName: "Stale completion")))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 0)
        let freshModel = LuminaViewModel(modelContext: container.mainContext)
        #expect(freshModel.saveRecord(MealLog(mealName: "New session entry")))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 1)
    }

    @Test func emptyOrFailedImportNeverBecomesASavablePhoto() async throws {
        let importer = LocalPhotoImport()
        var saved: [Data] = []
        let empty = importer.load(using: { Data() }, isCurrentSession: { true },
            onLoaded: { saved.append($0) })
        await empty.value
        #expect(importer.data == nil && importer.errorMessage != nil && !importer.isLoading)
        let failed = importer.load(using: { throw CocoaError(.fileReadNoSuchFile) },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await failed.value
        #expect(importer.data == nil && importer.errorMessage != nil && !importer.isLoading)
        #expect(saved.isEmpty)
        let validPNG = try photo(7)
        let invalidSelections = [Data("Nonempty unreadable provider data".utf8),
            Data(validPNG.dropLast()),
            try photo(8, width: JournalTransferLimits.standard.maximumPhotoDimension + 1, height: 1),
            Data(repeating: 0, count: JournalTransferLimits.standard.maximumPhotoBytes + 1)]
        for bytes in invalidSelections {
            let invalid = importer.load(using: { bytes }, isCurrentSession: { true },
                onLoaded: { saved.append($0) })
            await invalid.value
            #expect(importer.data == nil && importer.errorMessage != nil && !importer.isLoading)
            #expect(saved.isEmpty, "Rejected provider bytes must never reach a save callback")
        }
        for type in [UTType.png, .jpeg, .heic] {
            let original = try photo(9, type: type)
            let originalHash = SHA256.hash(data: original)
            let completed = importer.load(using: { original }, isCurrentSession: { true },
                onLoaded: { saved.append($0) })
            await completed.value
            #expect(!importer.isLoading && importer.errorMessage == nil)
            #expect(importer.data == original && saved.last == original)
            #expect(SHA256.hash(data: try #require(importer.data)) == originalHash,
                    "Validation must preserve the original selected image bytes")
        }
        #expect(saved.count == 3)
    }

    /// Real image fixtures keep the cancellation cases meaningful after the
    /// production import boundary starts rejecting arbitrary non-image bytes.
    private func photo(_ seed: UInt8, width: Int = 32, height: Int = 32,
                       type: UTType = .png) throws -> Data {
        var pixels = Data(count: width * height * 3)
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in bytes.indices { bytes[index] = seed &+ UInt8(truncatingIfNeeded: index) }
        }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 24, bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// Deliberately does not cooperate with Task cancellation: tests decide the
/// exact completion order and prove the production request/session checks.
@MainActor
private final class ControlledPhotoLoader {
    private var continuation: CheckedContinuation<Data?, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            precondition(self.continuation == nil)
            self.continuation = continuation
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(with result: Result<Data?, any Error>) {
        precondition(continuation != nil)
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
