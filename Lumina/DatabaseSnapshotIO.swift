import Foundation
import SQLite3
import CoreTransferable
import UniformTypeIdentifiers
import Darwin

nonisolated struct JournalTransferLimits: Sendable {
    var maximumFileBytes: Int64 = 512 * 1_024 * 1_024
    var maximumPhotoBytes = 16 * 1_024 * 1_024
    var maximumTotalPhotoBytes = 128 * 1_024 * 1_024
    var maximumPhotoFrames = 256
    var maximumPhotoDimension = 16_384
    var maximumTotalPhotoPixels: Int64 = 64_000_000
    var maximumRecordBytes = 2 * 1_024 * 1_024
    var maximumTotalRecordBytes = 64 * 1_024 * 1_024
    var maximumTextBytes = 1_024 * 1_024
    var maximumRecords = 10_000
    var deadlineSeconds: TimeInterval = 45
    static let standard = JournalTransferLimits()
}

nonisolated enum JournalTransferError: Error, Equatable, Sendable {
    case unsupported, invalid, tooLarge, timedOut, unavailable, nonempty, changed, readOnly, busy, rawRecoveryAvailable

    var messageKey: String {
        switch self {
        case .unsupported: return "This file is not a supported restorable Lumina backup. Older database exports are kept unchanged."
        case .invalid: return "The backup is damaged or contains unsupported records. Your journal has not changed."
        case .tooLarge: return "This backup exceeds the supported file, record or photo limits. Your journal has not changed."
        case .timedOut: return "The backup operation took too long and was stopped. Your journal has not changed."
        case .unavailable: return "The backup file could not be read or written. Check the available storage and try again."
        case .nonempty: return "Restore is available only when your local journal is empty. Existing records have not been changed."
        case .changed: return "Your journal changed while the backup was being prepared. Start the operation again."
        case .readOnly: return "This journal is read-only. It cannot receive restored records."
        case .busy: return "Finish or cancel the current backup operation before deleting local data."
        case .rawRecoveryAvailable: return "Some saved records exceed the supported recovery limits or format. You can export a raw recovery copy instead. Your journal has not changed."
        }
    }
}

nonisolated final class JournalTransferBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let deadline: TimeInterval

    init(seconds: TimeInterval) {
        deadline = ProcessInfo.processInfo.systemUptime + max(0, seconds)
    }

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
    var remainingSeconds: TimeInterval { max(0, deadline - ProcessInfo.processInfo.systemUptime) }
    var shouldStop: Bool { isCancelled || ProcessInfo.processInfo.systemUptime >= deadline }

    func check() throws {
        if isCancelled || Task.isCancelled { throw CancellationError() }
        if ProcessInfo.processInfo.systemUptime >= deadline { throw JournalTransferError.timedOut }
    }
}

nonisolated struct OwnedJournalFile: Sendable {
    let directory: URL
    let file: URL
    private let token: UUID

    fileprivate init(directory: URL, file: URL, token: UUID) {
        self.directory = directory; self.file = file; self.token = token
    }

    func remove() {
        // Only this operation's newly-created staging directory is removable.
        guard directory.lastPathComponent == "Lumina-Transfer-" + token.uuidString,
              file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

nonisolated enum JournalExportKind: Sendable {
    case restorable, rawRecovery

    var filename: String {
        switch self {
        case .restorable: return "Lumina-backup.sqlite"
        case .rawRecovery: return "Lumina-raw-recovery.sqlite"
        }
    }
}

nonisolated struct JournalExportFile: Transferable, Sendable {
    let file: URL
    let kind: JournalExportKind

    init(file: URL, kind: JournalExportKind = .restorable) {
        self.file = file; self.kind = kind
    }

    var filename: String { kind.filename }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .database) { item in
            SentTransferredFile(item.file, allowAccessingOriginalFile: false)
        }
        // The transferred item's filename is independent of the export dialog's
        // default. Supply a nonempty, app-owned name for the FileWrapper bridge.
        .suggestedFileName { $0.filename }
    }
}

/// Every handle is confined to one synchronous worker invocation. SQLite is
/// never given an application model object or a live destination store to edit.
nonisolated final class JournalSQLite {
    private(set) var handle: OpaquePointer?
    let budget: JournalTransferBudget

    init(url: URL, writable: Bool, budget: JournalTransferBudget, maximumValueBytes: Int) throws {
        self.budget = budget
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle); handle = nil
            throw JournalTransferError.unavailable
        }
        sqlite3_extended_result_codes(handle, 1)
        sqlite3_busy_timeout(handle, 25)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, Int32(clamping: maximumValueBytes))
        sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 16_384)
        sqlite3_limit(handle, SQLITE_LIMIT_EXPR_DEPTH, 32)
        sqlite3_limit(handle, SQLITE_LIMIT_COMPOUND_SELECT, 8)
        sqlite3_limit(handle, SQLITE_LIMIT_TRIGGER_DEPTH, 0)
        // The iOS SDK's SQLite header defines SQLITE_OMIT_LOAD_EXTENSION and
        // does not expose sqlite3_enable_load_extension. No enable/load call
        // is used; all SQL below and in recovery IO is fixed app-owned text.
        sqlite3_progress_handler(handle, 1_000, { raw in
            guard let raw else { return 1 }
            return Unmanaged<JournalTransferBudget>.fromOpaque(raw).takeUnretainedValue().shouldStop ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        do {
            try execute("PRAGMA trusted_schema=OFF")
            if !writable { try execute("PRAGMA query_only=ON") }
        } catch { close(); throw error }
    }

    deinit { close() }
    func close() {
        guard let handle else { return }
        sqlite3_progress_handler(handle, 0, nil, nil)
        sqlite3_close(handle)
        self.handle = nil
    }

    func execute(_ sql: String) throws {
        try budget.check()
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            try budget.check()
            throw JournalTransferError.invalid
        }
    }

    func statement(_ sql: String) throws -> OpaquePointer {
        try budget.check()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            try budget.check()
            throw JournalTransferError.invalid
        }
        return statement
    }

    func oneText(_ sql: String) throws -> String {
        let statement = try statement(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              let value = sqlite3_column_text(statement, 0) else {
            try budget.check(); throw JournalTransferError.invalid
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count <= 16_384,
              let result = String(bytes: UnsafeBufferPointer(start: value, count: count), encoding: .utf8),
              !result.utf8.contains(0) else { throw JournalTransferError.invalid }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            try budget.check(); throw JournalTransferError.invalid
        }
        return result
    }

    func oneInt(_ sql: String) throws -> Int64 {
        let statement = try statement(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else {
            try budget.check(); throw JournalTransferError.invalid
        }
        let result = sqlite3_column_int64(statement, 0)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            try budget.check(); throw JournalTransferError.invalid
        }
        return result
    }
}

/// Coordinate on one worker thread. Foundation explicitly permits cancel()
/// from another thread; no other coordinator operation crosses that boundary.
nonisolated final class JournalCoordinatedRead: @unchecked Sendable {
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    func cancel() { coordinator.cancel() }

    func read(_ selected: URL, budget: JournalTransferBudget,
              accessor: (URL) throws -> OwnedJournalFile) throws -> OwnedJournalFile {
        try budget.check()
        var coordinationError: NSError?
        var result: Result<OwnedJournalFile, Error>?
        coordinator.coordinate(readingItemAt: selected, options: .withoutChanges,
                               error: &coordinationError) { coordinated in
            result = Result { try budget.check(); return try accessor(coordinated) }
        }
        // Keep any completed owned result accounted for if cancellation or a
        // deadline arrives as the provider hands control back to this worker.
        do { try budget.check() }
        catch {
            if case .success(let owned) = result { owned.remove() }
            throw error
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw JournalTransferError.unavailable
    }
}

nonisolated enum DatabaseSnapshotIO {
    static var defaultParent: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-Journal-Transfer-v1", isDirectory: true)
    }
    static func create(source: URL, limits: JournalTransferLimits = .standard,
                       parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> OwnedJournalFile {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let task = Task.detached(priority: .userInitiated) {
            let owned = try makeOwnedFile(parent: parent, name: "snapshot.sqlite")
            do {
                try copyDatabase(source: source, target: owned.file, limits: limits, budget: budget)
                try budget.check()
                return owned
            } catch { owned.remove(); throw error }
        }
        return try await withTaskCancellationHandler {
            let owned = try await task.value
            do { try Task.checkCancellation(); return owned }
            catch { owned.remove(); throw error }
        } onCancel: { budget.cancel(); task.cancel() }
    }

    static func copyDatabase(source: URL, target: URL, limits: JournalTransferLimits,
                             budget: JournalTransferBudget) throws {
        try budget.check()
        guard !FileManager.default.fileExists(atPath: target.path) else { throw JournalTransferError.invalid }
        let input = try JournalSQLite(url: source, writable: false, budget: budget,
                                      maximumValueBytes: limits.maximumPhotoBytes + limits.maximumRecordBytes + 4_096)
        let pages = try input.oneInt("PRAGMA page_count")
        let pageSize = try input.oneInt("PRAGMA page_size")
        guard pages >= 0, pageSize > 0, pages <= limits.maximumFileBytes / pageSize else {
            throw JournalTransferError.tooLarge
        }
        let output = try JournalSQLite(url: target, writable: true, budget: budget,
                                       maximumValueBytes: limits.maximumPhotoBytes + limits.maximumRecordBytes + 4_096)
        guard let backup = sqlite3_backup_init(output.handle, "main", input.handle, "main") else {
            throw JournalTransferError.unavailable
        }
        var finished = false
        defer { if !finished { sqlite3_backup_finish(backup) } }
        while true {
            try budget.check()
            let result = sqlite3_backup_step(backup, 64)
            // The live store may grow while SQLite restarts an online backup.
            // Recheck the current page count before accepting another chunk.
            guard Int64(sqlite3_backup_pagecount(backup)) <= limits.maximumFileBytes / pageSize else {
                throw JournalTransferError.tooLarge
            }
            if result == SQLITE_DONE { break }
            if result == SQLITE_OK { continue }
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            try budget.check()
            throw JournalTransferError.unavailable
        }
        let result = sqlite3_backup_finish(backup); finished = true
        guard result == SQLITE_OK else { throw JournalTransferError.unavailable }
        guard try output.oneText("PRAGMA journal_mode=DELETE") == "delete" else { throw JournalTransferError.invalid }
        try budget.check()
        output.close(); input.close()
        try checkFile(target, maximumBytes: limits.maximumFileBytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    static func stageSelectedFile(_ selected: URL, limits: JournalTransferLimits = .standard,
                                  parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> OwnedJournalFile {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let coordinatedRead = JournalCoordinatedRead()
        let stopAtDeadline = DispatchWorkItem { coordinatedRead.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, limits.deadlineSeconds),
                                                       execute: stopAtDeadline)
        defer { stopAtDeadline.cancel() }
        let task = Task.detached(priority: .userInitiated) {
            let accessing = selected.startAccessingSecurityScopedResource()
            defer { if accessing { selected.stopAccessingSecurityScopedResource() } }
            try checkFile(selected, maximumBytes: limits.maximumFileBytes)
            return try coordinatedRead.read(selected, budget: budget) { file in
                try copyRegularFile(file, limits: limits, budget: budget, parent: parent)
            }
        }
        return try await withTaskCancellationHandler {
            let owned = try await task.value
            do { try Task.checkCancellation(); return owned }
            catch { owned.remove(); throw error }
        } onCancel: { budget.cancel(); coordinatedRead.cancel(); task.cancel() }
    }

    private static func copyRegularFile(_ selected: URL, limits: JournalTransferLimits,
                                         budget: JournalTransferBudget, parent: URL) throws -> OwnedJournalFile {
        guard !selected.path.utf8.contains(0) else { throw JournalTransferError.invalid }
        // NOFOLLOW closes the path-check/open race; NONBLOCK prevents a raced
        // FIFO from blocking open before its descriptor can be rejected.
        let descriptor = Darwin.open(selected.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw JournalTransferError.unavailable }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0,
              initial.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), initial.st_size >= 0 else {
            throw JournalTransferError.invalid
        }
        guard initial.st_size <= limits.maximumFileBytes else { throw JournalTransferError.tooLarge }
        let owned = try makeOwnedFile(parent: parent, name: "selected.sqlite")
        do {
            guard FileManager.default.createFile(atPath: owned.file.path, contents: nil,
                attributes: [.posixPermissions: 0o600]) else { throw JournalTransferError.unavailable }
            let output = try FileHandle(forWritingTo: owned.file)
            defer { try? output.close() }
            var copied: Int64 = 0
            while true {
                try budget.check()
                let chunk = try input.read(upToCount: 64 * 1_024) ?? Data()
                if chunk.isEmpty { break }
                copied += Int64(chunk.count)
                guard copied <= limits.maximumFileBytes else { throw JournalTransferError.tooLarge }
                try output.write(contentsOf: chunk)
            }
            var final = stat()
            guard fstat(descriptor, &final) == 0, copied == initial.st_size,
                  final.st_size == initial.st_size,
                  final.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
                  final.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec,
                  final.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec,
                  final.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec else {
                throw JournalTransferError.changed
            }
            try output.synchronize(); try budget.check()
            return owned
        } catch { owned.remove(); throw error }
    }

    static func checkFile(_ file: URL, maximumBytes: Int64) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0 else { throw JournalTransferError.invalid }
        guard Int64(size) <= maximumBytes else { throw JournalTransferError.tooLarge }
    }

    static func makeOwnedFile(parent: URL, name: String) throws -> OwnedJournalFile {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw JournalTransferError.invalid }
        if parent.standardizedFileURL == defaultParent.standardizedFileURL {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw JournalTransferError.invalid }
        }
        let token = UUID()
        let directory = parent.appendingPathComponent("Lumina-Transfer-" + token.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            try Data(("LuminaJournalTransfer:v1:" + token.uuidString).utf8)
                .write(to: directory.appendingPathComponent("ownership.txt"), options: .withoutOverwriting)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
        return OwnedJournalFile(directory: directory, file: directory.appendingPathComponent(name), token: token)
    }

    /// Caller must hold no active transfer lease. Never follows a symbolic link
    /// or removes an unknown directory, including a lookalike without ownership.
    static func removeAbandonedStaging(in parent: URL = DatabaseSnapshotIO.defaultParent) throws {
        guard FileManager.default.fileExists(atPath: parent.path) else { return }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw JournalTransferError.invalid }
        for directory in try FileManager.default.contentsOfDirectory(at: parent,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let prefix = "Lumina-Transfer-"
            guard directory.lastPathComponent.hasPrefix(prefix),
                  let token = UUID(uuidString: String(directory.lastPathComponent.dropFirst(prefix.count))),
                  directory.lastPathComponent == prefix + token.uuidString else { continue }
            let properties = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isDirectory == true, properties.isSymbolicLink != true else { continue }
            let marker = directory.appendingPathComponent("ownership.txt")
            guard FileManager.default.fileExists(atPath: marker.path) else { continue }
            let markerProperties = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard markerProperties.isRegularFile == true, markerProperties.isSymbolicLink != true,
                  let size = markerProperties.fileSize, size <= 128,
                  try Data(contentsOf: marker) == Data(("LuminaJournalTransfer:v1:" + token.uuidString).utf8) else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }
}
