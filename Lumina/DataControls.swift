import Foundation
import SwiftData
import SQLite3
import SwiftUI
import UniformTypeIdentifiers

struct DatabaseBackup: FileDocument {
    static let readableContentTypes: [UTType] = [.database]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension LuminaViewModel {
    func prepareDatabaseBackup(limits: JournalTransferLimits = .standard,
                               parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> OwnedJournalFile {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let snapshot = try await prepareRawDatabaseBackup(limits: limits, parent: parent)
        defer { snapshot.remove() }
        do {
            try Task.checkCancellation()
            // Only our own immutable snapshot reaches SwiftData. A selected
            // restore file never does. Capture yields between finite batches.
            let records = try await JournalRecordModels.captureTrustedSnapshot(snapshot.file, limits: limits, budget: budget)
            try Task.checkCancellation()
            try requireCurrentEditSession(); try budget.check()
            var remainingLimits = limits; remainingLimits.deadlineSeconds = budget.remainingSeconds
            let output = try await JournalRecoveryIO.finishExport(snapshot: snapshot, records: records, limits: remainingLimits, parent: parent)
            do { try Task.checkCancellation(); try requireCurrentEditSession(); try budget.check() }
            catch { output.remove(); throw error }
            return output
        } catch let error as JournalTransferError where [.unsupported, .invalid, .tooLarge, .timedOut].contains(error) {
            // The raw copy was possible, but current recovery limits/schema
            // cannot represent every saved record. Offer a separate explicit
            // raw-copy action; never silently label that copy as restorable.
            throw JournalTransferError.rawRecoveryAvailable
        }
    }

    func prepareRawDatabaseBackup(limits: JournalTransferLimits = .standard,
                                  parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> OwnedJournalFile {
        try requireCurrentEditSession()
        try modelContext.save()
        let configurations = modelContext.container.configurations
        guard configurations.count == 1, let configuration = configurations.first,
              !configuration.isStoredInMemoryOnly else { throw JournalTransferError.unavailable }
        let snapshot = try await DatabaseSnapshotIO.create(source: configuration.url, limits: limits, parent: parent)
        do { try Task.checkCancellation(); try requireCurrentEditSession(); return snapshot }
        catch { snapshot.remove(); throw error }
    }

    func journalHasRecords() throws -> Bool {
        for type in LuminaApp.modelTypes {
            if try journalRecordCount(type) > 0 { return true }
        }
        return false
    }

    private func journalRecordCount<T: PersistentModel>(_ type: T.Type) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<T>())
    }

    /// Import values into the existing empty container. There is no store-file
    /// replacement, migration of a selected file, merge, or preference import.
    func restoreJournal(_ preview: JournalRecoveryPreview,
                        limits: JournalTransferLimits = .standard,
                        beforeCommit: (() throws -> Void)? = nil) throws {
        try requireCurrentEditSession()
        guard modelContext.container.configurations.allSatisfy(\.allowsSave) else { throw JournalTransferError.readOnly }
        guard !modelContext.hasChanges else { throw JournalTransferError.changed }
        guard try !journalHasRecords() else { throw JournalTransferError.nonempty }
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        try budget.check()
        try preview.requireImportLimits(limits)
        let previousAutosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = previousAutosave }
        do {
            try modelContext.transaction {
                // Recheck at the mutation boundary, after preview. No await can
                // interleave another main-context operation with this transaction.
                guard try !journalHasRecords() else { throw JournalTransferError.nonempty }
                try JournalRecordModels.insert(preview.preparedRecords, into: modelContext, budget: budget)
                try beforeCommit?() // Fault-injection seam; the UI never supplies this.
                try budget.check()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        loadCurrentUser(); loadGoals(); loadPersistedCoachMemory()
        invalidateWorkoutsCache(); invalidateHabitsCache()
        // The normal view-model boot path refreshes locally saved snapshots and
        // widget display data. Language, reminder choices and keys are untouched.
    }
}

extension LuminaViewModel {
    @discardableResult
    func saveRecord<T: PersistentModel>(_ record: T) -> Bool {
        // ContentView creates a new model after deletion. Delayed work that
        // retained this obsolete model must never recreate cleared records.
        guard dataRevision == 0 else {
            errorMessage = L("These records were cleared. Return to Home before saving a new entry.")
            return false
        }
        guard modelContext.container.configurations.allSatisfy(\.allowsSave) else {
            errorMessage = L("This store is read-only. Your input has been kept.")
            return false
        }
        do {
            try modelContext.save()
            modelContext.insert(record)
            do { try modelContext.save() }
            catch { modelContext.rollback(); throw error }
            return true
        } catch {
            errorMessage = L("Could not save. Your input has been kept: %@", error.localizedDescription)
            return false
        }
    }

    func exportDatabase() throws -> Data {
        try modelContext.save()
        guard let config = modelContext.container.configurations.first, !config.isStoredInMemoryOnly else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var source: OpaquePointer?
        var target: OpaquePointer?
        defer { sqlite3_close(source); sqlite3_close(target) }
        guard sqlite3_open_v2(config.url.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(url.path, &target) == SQLITE_OK,
              let backup = sqlite3_backup_init(target, "main", source, "main") else {
            throw CocoaError(.fileReadUnknown)
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK,
              sqlite3_exec(target, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try Data(contentsOf: url)
    }

    func deleteAllLocalRecords() throws {
        guard !JournalTransferAdmission.shared.isBusy else { throw JournalTransferError.busy }
        // Clear only this feature's private temporary copies. Files chosen by
        // the user or exported to another destination are never removed here.
        try DatabaseSnapshotIO.removeAbandonedStaging()
        try modelContext.save()
        try modelContext.transaction {
            for type in LuminaApp.modelTypes { try deleteRecords(of: type) }
        }
        currentUser = nil
        recentHealthSnapshots = []
        persistedCoachMemory = []
        goals = []
        smartMemorySummary = ""
        coachDailyBriefing = ""
        proactiveHomeInsight = ""
        coachPhotoReflection = nil
        homeCoachSuggestions = []
        proactiveCoachRecommendation = ""
        showingProactiveRecommendation = false
        lastGeneratedAIPlan = nil
        lastWeeklyReflection = nil
        pendingVoiceMessage = nil
        invalidateWorkoutsCache()
        invalidateHabitsCache()
        CoachMemory.shared.clear()
        endCoachFocusLiveActivity()
        syncWidgetData()
        weeklyReminders?.setEnabled(false)
        dataRevision += 1
    }

    private func deleteRecords<T: PersistentModel>(of type: T.Type) throws {
        for record in try modelContext.fetch(FetchDescriptor<T>()) { modelContext.delete(record) }
    }
}
