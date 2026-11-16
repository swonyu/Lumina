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
    @discardableResult
    func saveRecord<T: PersistentModel>(_ record: T) -> Bool {
        guard modelContext.container.configurations.allSatisfy(\.allowsSave) else {
            errorMessage = "This store is read-only. Your input has been kept."
            return false
        }
        do {
            try modelContext.save()
            modelContext.insert(record)
            do { try modelContext.save() }
            catch { modelContext.rollback(); throw error }
            return true
        } catch {
            errorMessage = "Could not save. Your input has been kept: \(error.localizedDescription)"
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
        dataRevision += 1
    }

    private func deleteRecords<T: PersistentModel>(of type: T.Type) throws {
        for record in try modelContext.fetch(FetchDescriptor<T>()) { modelContext.delete(record) }
    }
}
