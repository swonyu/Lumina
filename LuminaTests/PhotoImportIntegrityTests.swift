import Foundation
import SwiftData
import Testing
@testable import Lumina

@MainActor
struct PhotoImportIntegrityTests {
    @Test func laterSelectionWinsWhenEarlierLoaderFinishesLast() async {
        let importer = LocalPhotoImport()
        let earlier = ControlledPhotoLoader()
        let later = ControlledPhotoLoader()
        var saved: [Data] = []
        let first = importer.load(using: { try await earlier.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await earlier.waitUntilStarted()
        let second = importer.load(using: { try await later.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await later.waitUntilStarted()
        later.finish(with: .success(Data([2, 2])))
        await second.value
        earlier.finish(with: .success(Data([1, 1])))
        await first.value
        #expect(importer.data == Data([2, 2]))
        #expect(saved == [Data([2, 2])])
        #expect(!importer.isLoading && importer.errorMessage == nil)
    }

    @Test func canceledLoaderCannotRefillClearedMealDraft() async {
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
        var saved: [Data] = []
        let pending = importer.load(using: { try await delayed.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await delayed.waitUntilStarted()
        importer.clear()
        delayed.finish(with: .success(Data([3])))
        await pending.value
        #expect(importer.data == nil && saved.isEmpty)
        #expect(!importer.isLoading && importer.errorMessage == nil)
    }

    @Test func leavingScreenCancelsPendingPhotoWithoutDiscardingCompletedPhoto() async {
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
        var saved: [Data] = []
        let pending = importer.load(using: { try await delayed.load() },
            isCurrentSession: { true }, onLoaded: { saved.append($0) })
        await delayed.waitUntilStarted()
        importer.cancelPending()
        delayed.finish(with: .success(Data([4])))
        await pending.value
        #expect(importer.data == nil && saved.isEmpty && !importer.isLoading)
        #expect(importer.errorMessage != nil)
        let completed = importer.load(using: { Data([5]) }, isCurrentSession: { true })
        await completed.value
        importer.cancelPending()
        #expect(importer.data == Data([5]) && importer.errorMessage == nil)
    }

    @Test func deletionInvalidatesImportAndStaleModelWrites() async throws {
        let schema = Schema(LuminaApp.modelTypes)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let model = LuminaViewModel(modelContext: container.mainContext)
        let importer = LocalPhotoImport()
        let delayed = ControlledPhotoLoader()
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
        delayed.finish(with: .success(Data([6])))
        await pending.value
        #expect(!callbackInvoked && importer.data == nil && !importer.isLoading)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ProgressPhoto>()) == 0)
        #expect(!model.saveRecord(MealLog(mealName: "Stale completion")))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 0)
        let freshModel = LuminaViewModel(modelContext: container.mainContext)
        #expect(freshModel.saveRecord(MealLog(mealName: "New session entry")))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealLog>()) == 1)
    }

    @Test func emptyOrFailedImportNeverBecomesASavablePhoto() async {
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
