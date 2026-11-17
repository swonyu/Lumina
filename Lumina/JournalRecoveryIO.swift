import Foundation
import SQLite3
import CryptoKit

nonisolated struct JournalRecoveryPreview: Identifiable, Sendable {
    let id = UUID()
    let owned: OwnedJournalFile
    let createdAt: Date
    let records: [JournalRecoveryRecord]
    let preparedRecords: [JournalPreparedRecord]
    let photoBytes: Int
    private let validationLimits: JournalTransferLimits
    var counts: [JournalRecordKind: Int] { Dictionary(grouping: records, by: \.kind).mapValues(\.count) }

    // Only the worker that has validated the owned immutable copy can construct
    // a preview. Views cannot turn arbitrary decoded values into import authority.
    fileprivate init(owned: OwnedJournalFile, createdAt: Date, records: [JournalRecoveryRecord],
                     preparedRecords: [JournalPreparedRecord], photoBytes: Int,
                     validationLimits: JournalTransferLimits) {
        self.owned = owned; self.createdAt = createdAt; self.records = records
        self.preparedRecords = preparedRecords; self.photoBytes = photoBytes
        self.validationLimits = validationLimits
    }

    func requireImportLimits(_ limits: JournalTransferLimits) throws {
        // A caller may not import under a stricter policy without preparing a
        // new preview under that policy. No untrusted parsing runs on MainActor.
        guard validationLimits.maximumFileBytes <= limits.maximumFileBytes,
              validationLimits.maximumPhotoBytes <= limits.maximumPhotoBytes,
              validationLimits.maximumTotalPhotoBytes <= limits.maximumTotalPhotoBytes,
              validationLimits.maximumPhotoFrames <= limits.maximumPhotoFrames,
              validationLimits.maximumPhotoDimension <= limits.maximumPhotoDimension,
              validationLimits.maximumTotalPhotoPixels <= limits.maximumTotalPhotoPixels,
              validationLimits.maximumRecordBytes <= limits.maximumRecordBytes,
              validationLimits.maximumTotalRecordBytes <= limits.maximumTotalRecordBytes,
              validationLimits.maximumTextBytes <= limits.maximumTextBytes,
              validationLimits.maximumRecords <= limits.maximumRecords else {
            throw JournalTransferError.tooLarge
        }
    }
}

/// Already-validated nested values are decoded on the file worker. The atomic
/// main-context import only constructs owned model instances and relationships.
nonisolated struct JournalPreparedRecord: Sendable {
    let record: JournalRecoveryRecord
    let stringLists: [String: [String]]
    let exercises: [JournalPortableExercise]?

    fileprivate init(_ record: JournalRecoveryRecord) throws {
        self.record = record
        switch record.kind {
        case .profile:
            stringLists = ["goalIDs": try record.stringList("goalIDs"),
                           "dietaryPreferences": try record.stringList("dietaryPreferences")]
            exercises = nil
        case .journal:
            stringLists = ["tags": try record.stringList("tags")]; exercises = nil
        case .workout:
            stringLists = [:]; exercises = try record.portableExercises()
        default: stringLists = [:]; exercises = nil
        }
    }

    func list(_ key: String) throws -> [String] {
        guard let value = stringLists[key] else { throw JournalTransferError.invalid }
        return value
    }
}

nonisolated enum JournalRecoveryIO {
    static let format = "com.swonyu.lumina.journal"
    static let version: Int64 = 1
    static let dateEpoch = "swift-reference-date-2001-01-01T00:00:00Z"
    static let headerSQL = "CREATE TABLE lumina_recovery_header (format TEXT NOT NULL, version INTEGER NOT NULL, created TEXT NOT NULL, record_count INTEGER NOT NULL, photo_bytes INTEGER NOT NULL, content_sha256 TEXT NOT NULL, date_epoch TEXT NOT NULL)"
    static let recordsSQL = "CREATE TABLE lumina_recovery_records (kind TEXT NOT NULL, record_id TEXT NOT NULL, payload BLOB NOT NULL, photo BLOB, row_sha256 TEXT NOT NULL, PRIMARY KEY(kind, record_id))"

    static func finishExport(snapshot: OwnedJournalFile, records: [JournalRecoveryRecord],
                             limits: JournalTransferLimits = .standard,
                             parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> OwnedJournalFile {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let task = Task.detached(priority: .userInitiated) {
            let output = try DatabaseSnapshotIO.makeOwnedFile(parent: parent, name: "Lumina-backup.sqlite")
            do {
                // The typed values came from this immutable snapshot. Copy it to
                // a separate output that has never been opened by SwiftData.
                try DatabaseSnapshotIO.copyDatabase(source: snapshot.file, target: output.file,
                                                    limits: limits, budget: budget)
                try writeRecords(records, to: output.file, limits: limits, budget: budget)
                try DatabaseSnapshotIO.checkFile(output.file, maximumBytes: limits.maximumFileBytes)
                try budget.check()
                return output
            } catch { output.remove(); throw error }
        }
        return try await withTaskCancellationHandler {
            let owned = try await task.value
            do { try Task.checkCancellation(); return owned }
            catch { owned.remove(); throw error }
        }
            onCancel: { budget.cancel(); task.cancel() }
    }

    static func prepareRestore(selected: URL, limits: JournalTransferLimits = .standard,
                               parent: URL = DatabaseSnapshotIO.defaultParent) async throws -> JournalRecoveryPreview {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let owned = try await DatabaseSnapshotIO.stageSelectedFile(selected, limits: limits, parent: parent)
        do {
            try budget.check()
            var remainingLimits = limits; remainingLimits.deadlineSeconds = budget.remainingSeconds
            let preview = try await readOwned(owned, limits: remainingLimits)
            try Task.checkCancellation()
            return preview
        }
        catch { owned.remove(); throw error }
    }

    static func readOwned(_ owned: OwnedJournalFile, limits: JournalTransferLimits = .standard) async throws -> JournalRecoveryPreview {
        let budget = JournalTransferBudget(seconds: limits.deadlineSeconds)
        let task = Task.detached(priority: .userInitiated) { try readRecords(owned, limits: limits, budget: budget) }
        return try await withTaskCancellationHandler {
            let preview = try await task.value
            try Task.checkCancellation()
            return preview
        }
            onCancel: { budget.cancel(); task.cancel() }
    }

    private static func writeRecords(_ records: [JournalRecoveryRecord], to file: URL,
                                     limits: JournalTransferLimits, budget: JournalTransferBudget) throws {
        try JournalRecoveryRecord.validateAll(records, limits: limits, budget: budget)
        let database = try JournalSQLite(url: file, writable: true, budget: budget,
                                         maximumValueBytes: limits.maximumPhotoBytes + limits.maximumRecordBytes + 4_096)
        guard try database.oneInt("SELECT count(*) FROM sqlite_master WHERE name IN ('lumina_recovery_header','lumina_recovery_records')") == 0 else {
            throw JournalTransferError.invalid
        }
        try database.execute("BEGIN IMMEDIATE")
        var committed = false
        defer { if !committed { try? database.execute("ROLLBACK") } }
        try database.execute(headerSQL); try database.execute(recordsSQL)
        let insert = try database.statement("INSERT INTO lumina_recovery_records(kind,record_id,payload,photo,row_sha256) VALUES(?,?,?,?,?)")
        defer { sqlite3_finalize(insert) }
        var totalPhotos = 0, contentHash = SHA256()
        let ordered = records.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
        for record in ordered {
            try budget.check()
            let payload = try record.payload(limits: limits)
            let rowHash = rowDigest(payload: payload, photo: record.photo)
            sqlite3_reset(insert); sqlite3_clear_bindings(insert)
            try bindText(record.kind.rawValue, at: 1, to: insert)
            try bindText(record.id, at: 2, to: insert)
            try bindData(payload, at: 3, to: insert)
            if let photo = record.photo { try bindData(photo, at: 4, to: insert) }
            else { guard sqlite3_bind_null(insert, 4) == SQLITE_OK else { throw JournalTransferError.invalid } }
            try bindText(rowHash, at: 5, to: insert)
            guard sqlite3_step(insert) == SQLITE_DONE else { try budget.check(); throw JournalTransferError.invalid }
            totalPhotos += record.photo?.count ?? 0
            contentHash.update(data: Data(rowHash.utf8))
        }
        let header = try database.statement("INSERT INTO lumina_recovery_header(format,version,created,record_count,photo_bytes,content_sha256,date_epoch) VALUES(?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(header) }
        try bindText(format, at: 1, to: header)
        guard sqlite3_bind_int64(header, 2, version) == SQLITE_OK,
              sqlite3_bind_int64(header, 4, Int64(records.count)) == SQLITE_OK,
              sqlite3_bind_int64(header, 5, Int64(totalPhotos)) == SQLITE_OK else { throw JournalTransferError.invalid }
        try bindText(JournalRecoveryRecord.bits(Date().timeIntervalSinceReferenceDate), at: 3, to: header)
        try bindText(hex(contentHash.finalize()), at: 6, to: header)
        try bindText(dateEpoch, at: 7, to: header)
        guard sqlite3_step(header) == SQLITE_DONE else { try budget.check(); throw JournalTransferError.invalid }
        try database.execute("COMMIT"); committed = true
        guard try database.oneText("PRAGMA quick_check(1)") == "ok" else { throw JournalTransferError.invalid }
    }

    private static func readRecords(_ owned: OwnedJournalFile, limits: JournalTransferLimits,
                                    budget: JournalTransferBudget) throws -> JournalRecoveryPreview {
        try DatabaseSnapshotIO.checkFile(owned.file, maximumBytes: limits.maximumFileBytes)
        let database = try JournalSQLite(url: owned.file, writable: false, budget: budget,
                                         maximumValueBytes: limits.maximumPhotoBytes + limits.maximumRecordBytes + 4_096)
        // A view, generated column or virtual table may not substitute for our
        // fixed real tables. No table/column name comes from the selected file.
        guard try database.oneInt("SELECT count(*) FROM sqlite_master WHERE name IN ('lumina_recovery_header','lumina_recovery_records') AND type='table'") == 2 else {
            throw JournalTransferError.unsupported
        }
        guard try database.oneText("SELECT sql FROM sqlite_master WHERE type='table' AND name='lumina_recovery_header'") == headerSQL,
              try database.oneText("SELECT sql FROM sqlite_master WHERE type='table' AND name='lumina_recovery_records'") == recordsSQL,
              try database.oneInt("SELECT count(*) FROM sqlite_master WHERE type='trigger' AND tbl_name IN ('lumina_recovery_header','lumina_recovery_records')") == 0 else {
            throw JournalTransferError.invalid
        }
        guard try database.oneText("PRAGMA quick_check(1)") == "ok" else { throw JournalTransferError.invalid }
        guard try database.oneInt("SELECT count(*) FROM lumina_recovery_header") == 1 else { throw JournalTransferError.invalid }
        let header = try database.statement("SELECT format,version,created,record_count,photo_bytes,content_sha256,date_epoch FROM lumina_recovery_header")
        defer { sqlite3_finalize(header) }
        guard sqlite3_step(header) == SQLITE_ROW else { try budget.check(); throw JournalTransferError.invalid }
        guard try columnText(header, 0, maximumBytes: 128) == format,
              sqlite3_column_type(header, 1) == SQLITE_INTEGER,
              sqlite3_column_int64(header, 1) == version,
              try columnText(header, 6, maximumBytes: 128) == dateEpoch else { throw JournalTransferError.unsupported }
        guard sqlite3_column_type(header, 3) == SQLITE_INTEGER, sqlite3_column_type(header, 4) == SQLITE_INTEGER else { throw JournalTransferError.invalid }
        let expectedCount = sqlite3_column_int64(header, 3), expectedPhotos = sqlite3_column_int64(header, 4)
        guard expectedCount >= 0, expectedCount <= Int64(limits.maximumRecords),
              expectedPhotos >= 0, expectedPhotos <= Int64(limits.maximumTotalPhotoBytes) else { throw JournalTransferError.tooLarge }
        let createdBits = try columnText(header, 2, maximumBytes: 16)
        let dateRecord = JournalRecoveryRecord(kind: .item, id: "", fields: ["created": createdBits], ownerID: nil, photo: nil)
        let created = try dateRecord.date("created")
        let expectedHash = try columnText(header, 5, maximumBytes: 64)
        guard isDigest(expectedHash), sqlite3_step(header) == SQLITE_DONE else { throw JournalTransferError.invalid }
        let count = try database.oneInt("SELECT count(*) FROM lumina_recovery_records")
        guard count == expectedCount else { throw JournalTransferError.invalid }
        let rows = try database.statement("SELECT kind,record_id,payload,photo,row_sha256 FROM lumina_recovery_records ORDER BY kind,record_id")
        defer { sqlite3_finalize(rows) }
        var records: [JournalRecoveryRecord] = [], photoBytes = 0, payloadBytes = 0, contentHash = SHA256()
        while true {
            try budget.check()
            let result = sqlite3_step(rows)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, records.count < limits.maximumRecords else {
                try budget.check(); throw JournalTransferError.invalid
            }
            let kind = try columnText(rows, 0, maximumBytes: 32)
            let id = try columnText(rows, 1, maximumBytes: 80)
            let payload = try columnData(rows, 2, maximumBytes: limits.maximumRecordBytes)
            guard payload.count <= limits.maximumTotalRecordBytes - payloadBytes else { throw JournalTransferError.tooLarge }
            payloadBytes += payload.count
            let photo: Data?
            if sqlite3_column_type(rows, 3) == SQLITE_NULL { photo = nil }
            else { photo = try columnData(rows, 3, maximumBytes: limits.maximumPhotoBytes) }
            let bytes = photo?.count ?? 0
            guard bytes <= limits.maximumTotalPhotoBytes - photoBytes else { throw JournalTransferError.tooLarge }
            photoBytes += bytes
            let savedHash = try columnText(rows, 4, maximumBytes: 64)
            guard isDigest(savedHash), savedHash == rowDigest(payload: payload, photo: photo) else { throw JournalTransferError.invalid }
            let record = try JournalRecoveryRecord.decode(payload, photo: photo, limits: limits, budget: budget)
            guard record.kind.rawValue == kind, record.id == id else { throw JournalTransferError.invalid }
            records.append(record); contentHash.update(data: Data(savedHash.utf8))
        }
        guard records.count == Int(expectedCount), photoBytes == Int(expectedPhotos),
              hex(contentHash.finalize()) == expectedHash else { throw JournalTransferError.invalid }
        try JournalRecoveryRecord.validateAll(records, limits: limits, budget: budget)
        try budget.check()
        var prepared: [JournalPreparedRecord] = []
        for record in records {
            try budget.check()
            prepared.append(try JournalPreparedRecord(record))
        }
        try budget.check()
        return JournalRecoveryPreview(owned: owned, createdAt: created, records: records,
            preparedRecords: prepared, photoBytes: photoBytes, validationLimits: limits)
    }

    static func rowDigest(payload: Data, photo: Data?) -> String {
        var hash = SHA256()
        var payloadLength = UInt64(payload.count).bigEndian
        withUnsafeBytes(of: &payloadLength) { hash.update(bufferPointer: $0) }
        hash.update(data: payload)
        hash.update(data: Data([photo == nil ? 0 : 1]))
        if let photo {
            var photoLength = UInt64(photo.count).bigEndian
            withUnsafeBytes(of: &photoLength) { hash.update(bufferPointer: $0) }
            hash.update(data: photo)
        }
        return hex(hash.finalize())
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isASCII && "0123456789abcdef".contains($0) }
    }
    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private static func bindText(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard value.withCString({ sqlite3_bind_text(statement, index, $0, -1, transient) }) == SQLITE_OK else { throw JournalTransferError.invalid }
    }
    private static func bindData(_ value: Data, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if value.isEmpty { result = sqlite3_bind_zeroblob(statement, index, 0) }
        else {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            result = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), transient) }
        }
        guard result == SQLITE_OK else { throw JournalTransferError.invalid }
    }
    private static func columnText(_ statement: OpaquePointer, _ index: Int32, maximumBytes: Int) throws -> String {
        guard sqlite3_column_type(statement, index) == SQLITE_TEXT else { throw JournalTransferError.invalid }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count <= maximumBytes else { throw JournalTransferError.tooLarge }
        guard let bytes = sqlite3_column_text(statement, index),
              let value = String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8),
              !value.utf8.contains(0) else { throw JournalTransferError.invalid }
        return value
    }
    private static func columnData(_ statement: OpaquePointer, _ index: Int32, maximumBytes: Int) throws -> Data {
        guard sqlite3_column_type(statement, index) == SQLITE_BLOB else { throw JournalTransferError.invalid }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count <= maximumBytes else { throw JournalTransferError.tooLarge }
        if count == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, index) else { throw JournalTransferError.invalid }
        return Data(bytes: bytes, count: count)
    }
}
