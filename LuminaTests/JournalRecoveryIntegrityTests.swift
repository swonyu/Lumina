import Foundation
import Testing
import SwiftData
import SQLite3
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable
@testable import Lumina

@MainActor
struct JournalRecoveryIntegrityTests {
    @Test func forcedWALSnapshotReopensAloneWithMultiMegabytePhotos() async throws {
        let fixture = try RecoveryFixture(name: "wal")
        defer { fixture.remove() }
        let reader = try SQLFixture(url: fixture.url)
        #expect(try reader.text("PRAGMA main.journal_mode") == "wal",
                "The recovery fixture must use the actual WAL journal mode")
        try reader.exec("BEGIN")
        _ = try reader.integer("SELECT count(*) FROM sqlite_master")
        let mealPhoto = try patternPhoto(minimumBytes: 3 * 1_024 * 1_024, seed: 17)
        let progressPhoto = try patternPhoto(minimumBytes: 2 * 1_024 * 1_024, seed: 91)
        #expect(mealPhoto.count >= 3 * 1_024 * 1_024 && progressPhoto.count >= 2 * 1_024 * 1_024)
        let profile = profileFixture()
        fixture.context.insert(profile)
        let meal = MealLog(mealName: "Uncheckpointed meal", notes: "Exact WAL sentinel", photoData: mealPhoto)
        meal.owner = profile; fixture.context.insert(meal)
        let photo = ProgressPhoto(photoData: progressPhoto); photo.owner = profile; fixture.context.insert(photo)
        try fixture.context.save()
        let checkpoint = try SQLFixture(url: fixture.url)
        // Open this connection's pager before asking for counters. Passing nil
        // requests all databases and SQLite explicitly leaves both output
        // counters undefined in that mode; a named main database is required.
        #expect(try checkpoint.text("PRAGMA main.journal_mode") == "wal")
        _ = try checkpoint.integer("SELECT count(*) FROM main.sqlite_master")
        var logFrames: Int32 = -1, copiedFrames: Int32 = -1
        let checkpointResult = sqlite3_wal_checkpoint_v2(checkpoint.handle, "main", SQLITE_CHECKPOINT_PASSIVE, &logFrames, &copiedFrames)
        #expect(checkpointResult == SQLITE_OK)
        #expect(logFrames > copiedFrames && copiedFrames >= 0,
                "Fixture must actually retain committed frames outside the main database")
        let snapshot = try await DatabaseSnapshotIO.create(source: fixture.url, parent: fixture.directory)
        defer { snapshot.remove() }
        try reader.exec("ROLLBACK")
        let independent = fixture.directory.appendingPathComponent("standalone.sqlite")
        try FileManager.default.copyItem(at: snapshot.file, to: independent)
        #expect(!FileManager.default.fileExists(atPath: independent.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: independent.path + "-shm"))
        let check = try SQLFixture(url: independent, writable: false)
        #expect(try check.text("PRAGMA quick_check(1)") == "ok")
        #expect(try check.text("PRAGMA journal_mode") == "delete")
        check.close()
        let reopened = try fixture.open(independent, allowsSave: false)
        defer { withExtendedLifetime(reopened) {} }
        let savedMeal = try #require(reopened.mainContext.fetch(FetchDescriptor<MealLog>()).first)
        let savedPhoto = try #require(reopened.mainContext.fetch(FetchDescriptor<ProgressPhoto>()).first)
        #expect(savedMeal.id == meal.id && savedMeal.owner?.id == profile.id)
        #expect(savedMeal.notes == "Exact WAL sentinel")
        #expect(savedMeal.photoData == mealPhoto && savedPhoto.photoData == progressPhoto)
        #expect(SHA256.hash(data: try #require(savedMeal.photoData)) == SHA256.hash(data: mealPhoto))
        #expect(savedPhoto.owner?.id == profile.id)

        // Current photo input has no historical16MiB cap. A lower injected
        // recovery limit proves oversized existing bytes remain exportable in
        // an explicitly nonrestorable raw copy, without relaxing typed restore.
        var limited = JournalTransferLimits.standard; limited.maximumPhotoBytes = 1_024 * 1_024
        await #expect(throws: JournalTransferError.rawRecoveryAvailable) {
            _ = try await fixture.model.prepareDatabaseBackup(limits: limited, parent: fixture.directory)
        }
        let raw = try await fixture.model.prepareRawDatabaseBackup(limits: limited, parent: fixture.directory)
        defer { raw.remove() }
        let rawHash = try hash(raw.file)
        let rawInspection = fixture.directory.appendingPathComponent("raw-inspection.sqlite")
        try FileManager.default.copyItem(at: raw.file, to: rawInspection)
        let rawReopened = try fixture.open(rawInspection, allowsSave: false)
        defer { withExtendedLifetime(rawReopened) {} }
        #expect(try rawReopened.mainContext.fetch(FetchDescriptor<MealLog>()).first?.photoData == mealPhoto)
        #expect(try rawReopened.mainContext.fetch(FetchDescriptor<ProgressPhoto>()).first?.photoData == progressPhoto)
        await #expect(throws: JournalTransferError.unsupported) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: raw.file, parent: fixture.directory)
        }
        #expect(try hash(raw.file) == rawHash)
    }

    @Test func typedRecoveryAndRawSnapshotShareOneCommittedState() async throws {
        let fixture = try RecoveryFixture(name: "parity")
        defer { fixture.remove() }
        try populateEveryModel(fixture.context, photoBytes: 2 * 1_024 * 1_024)
        let snapshot = try await DatabaseSnapshotIO.create(source: fixture.url, parent: fixture.directory)
        defer { snapshot.remove() }
        // Change the live journal after the snapshot exists. Neither export
        // representation may incorporate this later commit.
        let meal = try #require(fixture.context.fetch(FetchDescriptor<MealLog>()).first)
        meal.notes = "Later live change must be excluded"
        fixture.context.insert(JournalEntry(content: "Later live-only entry"))
        try fixture.context.save()
        let records = try await JournalRecordModels.captureTrustedSnapshot(snapshot.file, limits: .standard,
            budget: JournalTransferBudget(seconds: 45))
        let output = try await JournalRecoveryIO.finishExport(snapshot: snapshot, records: records, parent: fixture.directory)
        defer { output.remove() }
        let preview = try await JournalRecoveryIO.prepareRestore(selected: output.file, parent: fixture.directory)
        defer { preview.owned.remove() }
        #expect(preview.records == records)
        #expect(preview.preparedRecords.map(\.record) == records)
        #expect(preview.counts.count == 14 && preview.counts.values.allSatisfy { $0 == 1 })
        #expect(preview.records.first { $0.kind == .meal }?.fields["notes"] == "Meal note العربية")
        #expect(preview.records.filter { $0.kind == .journal }.count == 1)
        let reopened = try fixture.open(output.file, allowsSave: false)
        defer { withExtendedLifetime(reopened) {} }
        let rawRecords = try await JournalRecordModels.capture(reopened.mainContext, limits: .standard,
            budget: JournalTransferBudget(seconds: 45))
        #expect(rawRecords == records,
                "Adding recovery tables must leave the complete raw SwiftData snapshot readable and equivalent")
        #expect(try fixture.context.fetchCount(FetchDescriptor<JournalEntry>()) == 2)
        #expect(meal.notes == "Later live change must be excluded")
    }

    @Test func transactionalRestorePreservesAllFieldsRelationshipsAndUndoAfterReopen() async throws {
        let source = try RecoveryFixture(name: "source")
        let destination = try RecoveryFixture(name: "destination")
        defer { source.remove(); destination.remove() }
        try populateEveryModel(source.context, photoBytes: 2 * 1_024 * 1_024)
        let output = try await source.model.prepareDatabaseBackup(parent: source.directory)
        defer { output.remove() }
        let originalHash = try hash(output.file)
        let preview = try await JournalRecoveryIO.prepareRestore(selected: output.file, parent: destination.directory)
        defer { preview.owned.remove() }
        let preferenceSuite = "Lumina-Recovery-Test-" + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: preferenceSuite))
        defer { preferences.removePersistentDomain(forName: preferenceSuite) }
        preferences.set("ar", forKey: "appLanguage")
        preferences.set("synthetic-preserved-key", forKey: "unrelatedCredentialFixture")
        preferences.set(true, forKey: WeeklyReminderCoordinator.enabledKey)
        preferences.set("lumina-weekly-preserved-fixture", forKey: WeeklyReminderCoordinator.requestKey)
        let notificationClient = NoNotificationClient()
        let reminders = WeeklyReminderCoordinator(preferences: preferences, client: notificationClient)
        let destinationModel = LuminaViewModel(modelContext: destination.context, weeklyReminders: reminders)
        let language = LocalizationManager(preferences: preferences, preferredLanguages: ["en"], notificationCenter: NotificationCenter())
        try destinationModel.restoreJournal(preview)
        #expect(!destination.context.hasChanges)
        let reopened = try destination.open(destination.url, allowsSave: true)
        defer { withExtendedLifetime(reopened) {} }
        let restored = try await JournalRecordModels.capture(reopened.mainContext, limits: .standard,
            budget: JournalTransferBudget(seconds: 45))
        #expect(restored == preview.records)
        #expect(restored.count == 14)
        let restoredProfile = try #require(reopened.mainContext.fetch(FetchDescriptor<UserProfile>()).first)
        let restoredGoal = try #require(reopened.mainContext.fetch(FetchDescriptor<Goal>()).first)
        #expect(restoredProfile.createdAt.timeIntervalSinceReferenceDate.bitPattern == precisionMidnight.nextDown.bitPattern)
        #expect(restoredProfile.updatedAt.timeIntervalSinceReferenceDate.bitPattern == precisionMidnight.nextUp.bitPattern)
        let restoredAdjustment = try #require(restoredGoal.lastAdjustedByCoach)
        #expect(restoredAdjustment.timeIntervalSinceReferenceDate.bitPattern == precisionMidnight.nextDown.bitPattern)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(utc.component(.day, from: restoredProfile.createdAt) == 9)
        #expect(utc.component(.day, from: restoredProfile.updatedAt) == 10,
                "Reference-date bits must not round a saved instant across UTC midnight")
        #expect(preferences.string(forKey: "appLanguage") == "ar")
        #expect(preferences.string(forKey: "unrelatedCredentialFixture") == "synthetic-preserved-key")
        #expect(language.currentLanguage == .arabic)
        #expect(reminders.isEnabled && preferences.bool(forKey: WeeklyReminderCoordinator.enabledKey))
        #expect(preferences.string(forKey: WeeklyReminderCoordinator.requestKey) == "lumina-weekly-preserved-fixture")
        #expect(notificationClient.calls == 0,
                "The real injected reminder coordinator must not request, replace or remove notifications during record import")
        #expect(try hash(output.file) == originalHash)
        let habit = try #require(reopened.mainContext.fetch(FetchDescriptor<Habit>()).first)
        #expect(habit.totalCompletions == 5 && habit.currentStreak == 3 && habit.bestStreak == 7)
        habit.toggleCompletion(now: fixtureDate)
        try reopened.mainContext.save()
        #expect(habit.totalCompletions == 4 && habit.currentStreak == 2 && habit.bestStreak == 7)
        #expect(habit.lastCompletedDate == fixtureDate.addingTimeInterval(-86_400))

        // Habit undo has its own adapter. Check the stored Date bits directly,
        // then exercise the real Undo after an independent persistent reopen.
        let undoSource = try RecoveryFixture(name: "fractional-undo-source")
        let undoDestination = try RecoveryFixture(name: "fractional-undo-destination")
        defer { undoSource.remove(); undoDestination.remove() }
        let priorReference = (precisionMidnight + 43_200).nextDown
        let completedAt = Date(timeIntervalSinceReferenceDate: precisionMidnight + 86_400 + 43_200)
        let preciseHabit = Habit(name: "Fractional prior completion")
        preciseHabit.lastCompletedDate = Date(timeIntervalSinceReferenceDate: priorReference)
        preciseHabit.currentStreak = 2; preciseHabit.bestStreak = 7; preciseHabit.totalCompletions = 4
        preciseHabit.toggleCompletion(now: completedAt, calendar: utc)
        undoSource.context.insert(preciseHabit); try undoSource.context.save()
        let undoOutput = try await undoSource.model.prepareDatabaseBackup(parent: undoSource.directory)
        defer { undoOutput.remove() }
        let undoPreview = try await JournalRecoveryIO.prepareRestore(selected: undoOutput.file, parent: undoDestination.directory)
        defer { undoPreview.owned.remove() }
        try undoDestination.model.restoreJournal(undoPreview)
        let undoReopened = try undoDestination.open(undoDestination.url, allowsSave: true)
        defer { withExtendedLifetime(undoReopened) {} }
        let restoredUndoHabit = try #require(undoReopened.mainContext.fetch(FetchDescriptor<Habit>()).first)
        let savedPriorDate = try #require(restoredUndoHabit.journalRecoveryUndo.undoPreviousCompletionDate)
        #expect(savedPriorDate.timeIntervalSinceReferenceDate.bitPattern == priorReference.bitPattern)
        #expect(restoredUndoHabit.totalCompletions == 5 && restoredUndoHabit.currentStreak == 3 && restoredUndoHabit.bestStreak == 7)
        restoredUndoHabit.toggleCompletion(now: completedAt, calendar: utc)
        try undoReopened.mainContext.save()
        let undoneDate = try #require(restoredUndoHabit.lastCompletedDate)
        #expect(undoneDate.timeIntervalSinceReferenceDate.bitPattern == priorReference.bitPattern)
        #expect(restoredUndoHabit.totalCompletions == 4 && restoredUndoHabit.currentStreak == 2 && restoredUndoHabit.bestStreak == 7)
    }

    @Test func restoreRefusesNonemptyDirtyAndReadOnlyJournalsWithoutMutation() async throws {
        let source = try RecoveryFixture(name: "restore-guards")
        let destination = try RecoveryFixture(name: "guard-destination")
        defer { source.remove(); destination.remove() }
        try populateEveryModel(source.context, photoBytes: 64)
        let output = try await source.model.prepareDatabaseBackup(parent: source.directory)
        defer { output.remove() }
        let preview = try await JournalRecoveryIO.prepareRestore(selected: output.file, parent: destination.directory)
        defer { preview.owned.remove() }
        let existing = JournalEntry(content: "Existing entry must survive")
        destination.context.insert(existing); try destination.context.save()
        #expect(throws: JournalTransferError.nonempty) { try destination.model.restoreJournal(preview) }
        #expect(try destination.context.fetchCount(FetchDescriptor<JournalEntry>()) == 1)
        #expect(try destination.context.fetch(FetchDescriptor<JournalEntry>()).first?.id == existing.id)
        #expect(try destination.context.fetchCount(FetchDescriptor<MealLog>()) == 0)
        let readOnly = try destination.open(destination.url, allowsSave: false)
        defer { withExtendedLifetime(readOnly) {} }
        #expect(throws: JournalTransferError.readOnly) { try LuminaViewModel(modelContext: readOnly.mainContext).restoreJournal(preview) }
        let empty = try RecoveryFixture(name: "dirty")
        defer { empty.remove() }
        empty.context.autosaveEnabled = false
        let draft = JournalEntry(content: "Pending input")
        empty.context.insert(draft)
        #expect(throws: JournalTransferError.changed) { try empty.model.restoreJournal(preview) }
        #expect(empty.context.hasChanges)
        #expect(draft.content == "Pending input")
        #expect(try empty.context.fetchCount(FetchDescriptor<MealLog>()) == 0)
        let timed = try RecoveryFixture(name: "expired-import")
        defer { timed.remove() }
        var expired = JournalTransferLimits.standard; expired.deadlineSeconds = 0
        #expect(throws: JournalTransferError.timedOut) { try timed.model.restoreJournal(preview, limits: expired) }
        #expect(try !timed.model.journalHasRecords())
        #expect(!timed.context.hasChanges)
        var stricter = JournalTransferLimits.standard; stricter.maximumRecords = 1
        #expect(throws: JournalTransferError.tooLarge) { try timed.model.restoreJournal(preview, limits: stricter) }
        #expect(try !timed.model.journalHasRecords() && !timed.context.hasChanges,
                "A prepared preview cannot bypass a stricter import policy")
    }

    @Test func failureBeforeCommitRollsBackEveryImportedModelAndCanRetry() async throws {
        let source = try RecoveryFixture(name: "rollback-source")
        let destination = try RecoveryFixture(name: "rollback-destination")
        defer { source.remove(); destination.remove() }
        try populateEveryModel(source.context, photoBytes: 64)
        let output = try await source.model.prepareDatabaseBackup(parent: source.directory)
        defer { output.remove() }
        let preview = try await JournalRecoveryIO.prepareRestore(selected: output.file, parent: destination.directory)
        defer { preview.owned.remove() }
        enum InjectedFailure: Error { case beforeCommit }
        #expect(throws: InjectedFailure.self) {
            try destination.model.restoreJournal(preview) { throw InjectedFailure.beforeCommit }
        }
        #expect(!destination.context.hasChanges)
        #expect(try !destination.model.journalHasRecords())
        let reopened = try destination.open(destination.url, allowsSave: false)
        defer { withExtendedLifetime(reopened) {} }
        #expect(try !LuminaViewModel(modelContext: reopened.mainContext).journalHasRecords())
        try destination.model.restoreJournal(preview)
        #expect(try destination.context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try destination.context.fetchCount(FetchDescriptor<Goal>()) == 1)
        #expect(!destination.context.hasChanges)
    }

    @Test func oldMalformedViewSubstitutionAndFutureVersionFilesAreRejectedUnchanged() async throws {
        let fixture = try RecoveryFixture(name: "untrusted")
        defer { fixture.remove() }
        try populateEveryModel(fixture.context, photoBytes: 64)
        let raw = fixture.directory.appendingPathComponent("historical.sqlite")
        try fixture.model.exportDatabase().write(to: raw)
        let rawHash = try hash(raw)
        await #expect(throws: JournalTransferError.unsupported) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: raw, parent: fixture.directory)
        }
        #expect(try hash(raw) == rawHash)
        let malformed = fixture.directory.appendingPathComponent("damaged.sqlite")
        try Data("not a database".utf8).write(to: malformed)
        let malformedHash = try hash(malformed)
        await #expect(throws: (any Error).self) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: malformed, parent: fixture.directory)
        }
        #expect(try hash(malformed) == malformedHash)
        let view = fixture.directory.appendingPathComponent("substituted.sqlite")
        let fake = try SQLFixture(url: view)
        try fake.exec("CREATE VIEW lumina_recovery_header AS SELECT 1")
        try fake.exec(JournalRecoveryIO.recordsSQL)
        fake.close()
        let viewHash = try hash(view)
        await #expect(throws: JournalTransferError.unsupported) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: view, parent: fixture.directory)
        }
        #expect(try hash(view) == viewHash)
        let output = try await fixture.model.prepareDatabaseBackup(parent: fixture.directory)
        defer { output.remove() }
        let checksumFile = fixture.directory.appendingPathComponent("checksum.sqlite")
        try FileManager.default.copyItem(at: output.file, to: checksumFile)
        let corrupted = try SQLFixture(url: checksumFile)
        try corrupted.exec("UPDATE lumina_recovery_records SET row_sha256='0000000000000000000000000000000000000000000000000000000000000000'")
        corrupted.close()
        let checksumHash = try hash(checksumFile)
        await #expect(throws: JournalTransferError.invalid) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: checksumFile, parent: fixture.directory)
        }
        #expect(try hash(checksumFile) == checksumHash)
        let foreignEpochFile = fixture.directory.appendingPathComponent("foreign-date-epoch.sqlite")
        try FileManager.default.copyItem(at: output.file, to: foreignEpochFile)
        let foreignEpoch = try SQLFixture(url: foreignEpochFile)
        try foreignEpoch.exec("UPDATE lumina_recovery_header SET date_epoch='unix-1970-01-01T00:00:00Z'")
        foreignEpoch.close()
        let foreignEpochHash = try hash(foreignEpochFile)
        await #expect(throws: JournalTransferError.unsupported) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: foreignEpochFile, parent: fixture.directory)
        }
        #expect(try hash(foreignEpochFile) == foreignEpochHash,
                "A different date epoch must be rejected before any values are imported")
        let edited = try SQLFixture(url: output.file)
        try edited.exec("UPDATE lumina_recovery_header SET version=999")
        edited.close()
        let futureHash = try hash(output.file)
        await #expect(throws: JournalTransferError.unsupported) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: output.file, parent: fixture.directory)
        }
        #expect(try hash(output.file) == futureHash)
    }

    @Test func typedRecordsRejectUnknownFieldsDuplicateIDsDanglingOwnersAndDeepJSON() async throws {
        let fixture = try RecoveryFixture(name: "typed-validation")
        defer { fixture.remove() }
        try populateEveryModel(fixture.context, photoBytes: 64)
        let records = try await JournalRecordModels.capture(fixture.context, limits: .standard,
            budget: JournalTransferBudget(seconds: 45))
        let meal = try #require(records.first { $0.kind == .meal })
        var unknown = meal; unknown.fields["unreviewedFutureField"] = "value"
        #expect(throws: JournalTransferError.invalid) { try unknown.validate(limits: .standard) }
        #expect(throws: JournalTransferError.invalid) { try JournalRecoveryRecord.validateAll(records + [meal], limits: .standard) }
        var dangling = meal; dangling.ownerID = UUID().uuidString
        #expect(throws: JournalTransferError.invalid) {
            try JournalRecoveryRecord.validateAll(records.filter { $0.id != meal.id } + [dangling], limits: .standard)
        }
        var invalidProfile = try #require(records.first { $0.kind == .profile })
        invalidProfile.fields["goalIDs"] = "[]"
        #expect(throws: JournalTransferError.invalid) {
            try JournalRecoveryRecord.validateAll(records.filter { $0.kind != .profile } + [invalidProfile], limits: .standard)
        }
        let deeplyNested = Data((String(repeating: "[", count: 30) + "0" + String(repeating: "]", count: 30)).utf8)
        #expect(throws: JournalTransferError.invalid) { _ = try JournalRecoveryRecord.decode(deeplyNested, photo: nil, limits: .standard) }
        var hugeCounter = try #require(records.first { $0.kind == .habit })
        hugeCounter.fields["totalCompletions"] = String(Int.max)
        #expect(throws: JournalTransferError.invalid) { try hugeCounter.validate(limits: .standard) }
        var malformedPhoto = meal; malformedPhoto.photo = Data("not an image".utf8)
        #expect(throws: JournalTransferError.invalid) { try malformedPhoto.validate(limits: .standard) }
        let validPNG = try patternPhoto(minimumBytes: 32 * 1_024, seed: 33)
        let pngSource = try #require(CGImageSourceCreateWithData(validPNG as CFData, nil))
        let pixels = try #require(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))
        let jpegData = NSMutableData()
        let jpegDestination = try #require(CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(jpegDestination, pixels, nil)
        #expect(CGImageDestinationFinalize(jpegDestination))
        for complete in [validPNG, jpegData as Data] {
            var readable = meal; readable.photo = complete
            let originalPhotoHash = SHA256.hash(data: complete)
            try readable.validate(limits: .standard)
            #expect(SHA256.hash(data: try #require(readable.photo)) == originalPhotoHash)
            let partial = Data(complete.prefix(complete.count / 2))
            let recognizable = try #require(CGImageSourceCreateWithData(partial as CFData, nil))
            #expect(CGImageSourceGetType(recognizable) != nil)
            #expect(CGImageSourceCopyPropertiesAtIndex(recognizable, 0, nil) != nil,
                    "The damaged real image must still expose metadata, unlike random invalid bytes")
            var truncated = meal; truncated.photo = partial
            #expect(throws: JournalTransferError.invalid) { try truncated.validate(limits: .standard) }
            for missing in [1, 12] {
                var missingTail = meal; missingTail.photo = Data(complete.dropLast(missing))
                #expect(throws: JournalTransferError.invalid) { try missingTail.validate(limits: .standard) }
            }
        }
        // A preview is not enough: preserve complete images exactly, while
        // rejecting missing container tails across additional import formats.
        for type in [UTType.heic, .gif, .tiff] {
            let encoded = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(encoded, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, pixels, nil)
            #expect(CGImageDestinationFinalize(destination))
            let complete = encoded as Data
            var readable = meal; readable.photo = complete
            let before = SHA256.hash(data: complete)
            try readable.validate(limits: .standard)
            #expect(SHA256.hash(data: try #require(readable.photo)) == before)
            for remaining in [complete.count / 2, complete.count - 1, complete.count - 12] {
                var truncated = meal; truncated.photo = Data(complete.prefix(remaining))
                #expect(throws: JournalTransferError.invalid) { try truncated.validate(limits: .standard) }
            }
        }
        // A structurally complete PNG with a corrupted chunk checksum must
        // not become a restorable record even if a decoder repairs its preview.
        var corruptPNG = validPNG
        corruptPNG[29] ^= 1 // IHDR CRC; preserve signature, dimensions and IEND.
        var checksumPhoto = meal; checksumPhoto.photo = corruptPNG
        #expect(throws: JournalTransferError.invalid) { try checksumPhoto.validate(limits: .standard) }
        // A retained JPEG thumbnail/APP EOI cannot stand in for the outer EOI.
        let appPayload = Data([0xff, 0xef, 0x00, 0x06, 0xff, 0xd9, 0x00, 0x00])
        let jpeg = jpegData as Data
        var completeWithAPP = Data(jpeg.prefix(2)); completeWithAPP.append(appPayload)
        completeWithAPP.append(jpeg.dropFirst(2))
        var completeAPPPhoto = meal; completeAPPPhoto.photo = completeWithAPP
        try completeAPPPhoto.validate(limits: .standard)
        #expect(completeAPPPhoto.photo == completeWithAPP)
        var misleadingJPEG = Data(jpeg.prefix(2)); misleadingJPEG.append(appPayload)
        misleadingJPEG.append(jpeg.dropFirst(2).dropLast(2))
        var embeddedEOI = meal; embeddedEOI.photo = misleadingJPEG
        #expect(throws: JournalTransferError.invalid) { try embeddedEOI.validate(limits: .standard) }
        var workout = try #require(records.first { $0.kind == .workout })
        let tooManySets = try JSONSerialization.data(withJSONObject: (0..<201).map { _ in
            ["id": UUID().uuidString, "reps": 8] as [String: Any]
        }, options: [.sortedKeys])
        let oversizedSetsJSON = String(decoding: tooManySets, as: UTF8.self)
        for (first, second) in [(oversizedSetsJSON, "[]"), ("[]", oversizedSetsJSON)] {
            workout.fields["exercises"] = "[{\"id\":\"" + UUID().uuidString + "\",\"name\":\"Duplicate-key fixture\",\"sets\":" + first + ",\"sets\":" + second + "}]"
            do {
                let decoded = try workout.portableExercises()
                #expect(decoded.count <= 200 && decoded.allSatisfy { $0.sets.count <= 200 },
                        "Conflicting duplicate keys must never bypass bounds on the actual prepared values")
            } catch let error as JournalTransferError {
                #expect(error == .invalid || error == .tooLarge)
            }
        }
        var pixelLimit = JournalTransferLimits.standard; pixelLimit.maximumTotalPhotoPixels = 1
        #expect(throws: JournalTransferError.tooLarge) { try meal.validate(limits: pixelLimit) }
        var dimensionLimit = JournalTransferLimits.standard; dimensionLimit.maximumPhotoDimension = 1
        #expect(throws: JournalTransferError.tooLarge) { try meal.validate(limits: dimensionLimit) }
        var noPhoto = meal; noPhoto.photo = nil
        var emptyPhoto = meal; emptyPhoto.photo = Data()
        #expect(JournalRecoveryIO.rowDigest(payload: try noPhoto.payload(limits: .standard), photo: nil)
            != JournalRecoveryIO.rowDigest(payload: try emptyPhoto.payload(limits: .standard), photo: Data()))
    }

    @Test func cancellationDeadlineAndSizeLimitsCleanOnlyOwnedStaging() async throws {
        let fixture = try RecoveryFixture(name: "limits")
        defer { fixture.remove() }
        fixture.context.insert(JournalEntry(content: "Source survives")); try fixture.context.save()
        let sentinel = fixture.directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path))
        let task = Task { try await DatabaseSnapshotIO.create(source: fixture.url, parent: fixture.directory) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        var deadline = JournalTransferLimits.standard; deadline.deadlineSeconds = 0
        await #expect(throws: JournalTransferError.timedOut) {
            _ = try await DatabaseSnapshotIO.create(source: fixture.url, limits: deadline, parent: fixture.directory)
        }
        var small = JournalTransferLimits.standard; small.maximumFileBytes = 1
        await #expect(throws: JournalTransferError.tooLarge) {
            _ = try await DatabaseSnapshotIO.create(source: fixture.url, limits: small, parent: fixture.directory)
        }
        let oversized = fixture.directory.appendingPathComponent("oversized.sqlite")
        try Data(repeating: 7, count: 2_048).write(to: oversized)
        let oversizedHash = try hash(oversized)
        small.maximumFileBytes = 1_024
        await #expect(throws: JournalTransferError.tooLarge) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: oversized, limits: small, parent: fixture.directory)
        }
        #expect(try hash(oversized) == oversizedHash)
        let link = fixture.directory.appendingPathComponent("link.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url)
        await #expect(throws: JournalTransferError.invalid) {
            _ = try await JournalRecoveryIO.prepareRestore(selected: link, parent: fixture.directory)
        }
        #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path))
        #expect(after.subtracting(before) == ["oversized.sqlite", "link.sqlite"])
        #expect(try fixture.context.fetch(FetchDescriptor<JournalEntry>()).first?.content == "Source survives")

        // Crash-left cleanup must remove only a positively owned staging
        // directory, preserving plausible names, incorrect markers and links.
        let abandoned = try DatabaseSnapshotIO.makeOwnedFile(parent: fixture.directory, name: "private.sqlite")
        try Data("Owned private copy".utf8).write(to: abandoned.file)
        let lookalike = fixture.directory.appendingPathComponent("Lumina-Transfer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: lookalike, withIntermediateDirectories: false)
        let unrelatedMarker = lookalike.appendingPathComponent("ownership.txt")
        try Data("Not a Lumina transfer marker".utf8).write(to: unrelatedMarker)
        let markerToken = UUID()
        let linkedMarkerDirectory = fixture.directory.appendingPathComponent("Lumina-Transfer-" + markerToken.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: linkedMarkerDirectory, withIntermediateDirectories: false)
        let retainedMarker = fixture.directory.appendingPathComponent("retained-marker.txt")
        try Data(("LuminaJournalTransfer:v1:" + markerToken.uuidString).utf8).write(to: retainedMarker)
        let linkedMarker = linkedMarkerDirectory.appendingPathComponent("ownership.txt")
        try FileManager.default.createSymbolicLink(at: linkedMarker, withDestinationURL: retainedMarker)
        let linkToken = UUID()
        let linkTarget = fixture.directory.appendingPathComponent("retained-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: linkTarget, withIntermediateDirectories: false)
        let targetMarker = linkTarget.appendingPathComponent("ownership.txt")
        try Data(("LuminaJournalTransfer:v1:" + linkToken.uuidString).utf8).write(to: targetMarker)
        let linkedDirectory = fixture.directory.appendingPathComponent("Lumina-Transfer-" + linkToken.uuidString)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: linkTarget)
        let sourceBeforeCleanup = try hash(fixture.url)
        try DatabaseSnapshotIO.removeAbandonedStaging(in: fixture.directory)
        #expect(!FileManager.default.fileExists(atPath: abandoned.directory.path))
        #expect(try Data(contentsOf: unrelatedMarker) == Data("Not a Lumina transfer marker".utf8))
        #expect(try linkedMarker.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try linkedDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try Data(contentsOf: targetMarker) == Data(("LuminaJournalTransfer:v1:" + linkToken.uuidString).utf8))
        #expect(try Data(contentsOf: retainedMarker) == Data(("LuminaJournalTransfer:v1:" + markerToken.uuidString).utf8))
        #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
        #expect(try hash(fixture.url) == sourceBeforeCleanup)
        #expect(try fixture.context.fetch(FetchDescriptor<JournalEntry>()).first?.content == "Source survives")
    }

    @Test func canceledControllerRetainsAdmissionUntilItsActualWorkerStops() async throws {
        let fixture = try RecoveryFixture(name: "admission")
        defer { fixture.remove() }
        let admission = JournalTransferAdmission()
        let worker = ControlledExport()
        let first = JournalTransferController(admission: admission, exporter: worker.prepare)
        let second = JournalTransferController(admission: admission, exporter: worker.prepare)
        defer {
            first.cancelPreparation(); second.cancelPreparation()
            worker.finishPending(throwing: CancellationError())
            first.finishedExport(); second.finishedExport()
        }
        first.beginExport(using: fixture.model)
        try await waitUntil { worker.calls == 1 && worker.isPending }
        first.cancelPreparation()
        second.beginExport(using: fixture.model)
        #expect(worker.calls == 1 && admission.isBusy)
        #expect(first.isWorking && !second.isWorking)
        #expect(second.errorKey == "Another backup operation is finishing. Wait for it to stop before trying again.")
        let stale = try DatabaseSnapshotIO.makeOwnedFile(parent: fixture.directory, name: "late.sqlite")
        try Data("synthetic delayed worker result".utf8).write(to: stale.file)
        worker.finishPending(returning: stale)
        try await waitUntil { !first.isWorking && !admission.isBusy }
        #expect(!first.exporting && first.exportFile == nil)
        #expect(!FileManager.default.fileExists(atPath: stale.directory.path),
                "A canceled late result must be removed instead of becoming a new export")
        second.beginExport(using: fixture.model)
        try await waitUntil { worker.calls == 2 && worker.isPending }
        let current = try DatabaseSnapshotIO.makeOwnedFile(parent: fixture.directory, name: "current.sqlite")
        try Data("synthetic current worker result".utf8).write(to: current.file)
        worker.finishPending(returning: current)
        try await waitUntil { second.exporting && !second.isWorking }
        #expect(second.exportFile?.file == current.file && admission.isBusy,
                "The prepared file retains ownership until its export presentation finishes")
        #expect(second.exportFile?.suggestedFilename == "Lumina-backup.sqlite",
                "The actual Transferable representation must supply a nonempty filename to the native picker")
        #expect(second.exportFile?.suggestedFilename == second.exportFilename)
        #expect(!first.exporting && first.exportFile == nil)
        second.finishedExport()
        #expect(!admission.isBusy)
        #expect(!FileManager.default.fileExists(atPath: current.directory.path))

        var discarded: JournalTransferController? = JournalTransferController(admission: admission, exporter: worker.prepare)
        weak var discardedReference = discarded
        discarded?.beginExport(using: fixture.model)
        try await waitUntil { worker.calls == 3 && worker.isPending }
        let abandoned = try DatabaseSnapshotIO.makeOwnedFile(parent: fixture.directory, name: "abandoned.sqlite")
        try Data("Discarded presentation copy".utf8).write(to: abandoned.file)
        worker.finishPending(returning: abandoned)
        try await waitUntil { discarded?.exporting == true && discarded?.isWorking == false }
        #expect(admission.isBusy)
        discarded = nil
        try await waitUntil { discardedReference == nil && !admission.isBusy }
        #expect(!FileManager.default.fileExists(atPath: abandoned.directory.path),
                "A discarded, completed presentation must release only its own private file and lease")

        var rawCalls = 0
        let explicitRaw = try DatabaseSnapshotIO.makeOwnedFile(parent: fixture.directory, name: "explicit-raw.sqlite")
        try Data("Synthetic prepared raw worker result".utf8).write(to: explicitRaw.file)
        let fallback = JournalTransferController(admission: admission,
            exporter: { _ in throw JournalTransferError.rawRecoveryAvailable },
            rawExporter: { _ in rawCalls += 1; return explicitRaw })
        defer { fallback.cancelPreparation(); fallback.finishedExport(); explicitRaw.remove() }
        fallback.beginExport(using: fixture.model)
        try await waitUntil { !fallback.isWorking }
        #expect(fallback.canOfferRawCopy && !fallback.exporting && rawCalls == 0,
                "Raw recovery must require a separate explicit user action")
        fallback.beginRawExport(using: fixture.model)
        try await waitUntil { fallback.exporting && !fallback.isWorking }
        #expect(rawCalls == 1 && fallback.exportFilename == "Lumina-raw-recovery.sqlite")
        #expect(fallback.exportFile?.file == explicitRaw.file && admission.isBusy)
        #expect(fallback.exportFile?.suggestedFilename == "Lumina-raw-recovery.sqlite")
        #expect(fallback.exportFile?.suggestedFilename == fallback.exportFilename)
        fallback.finishedExport()
        #expect(!admission.isBusy && !FileManager.default.fileExists(atPath: explicitRaw.directory.path))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else { throw JournalTransferError.timedOut }
            await Task.yield()
        }
    }

    @MainActor private final class ControlledExport {
        private(set) var calls = 0
        private var continuation: CheckedContinuation<OwnedJournalFile, Error>?
        var isPending: Bool { continuation != nil }
        func prepare(_ model: LuminaViewModel) async throws -> OwnedJournalFile {
            calls += 1
            // Deliberately noncooperative, like a provider read already in flight.
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func finishPending(returning file: OwnedJournalFile) {
            let pending = continuation; continuation = nil; pending?.resume(returning: file)
        }
        func finishPending(throwing error: Error) {
            let pending = continuation; continuation = nil; pending?.resume(throwing: error)
        }
    }

    @MainActor private final class NoNotificationClient: WeeklyReminderClient {
        private(set) var calls = 0
        func pendingIdentifiers() async -> [String] { calls += 1; return [] }
        func isAuthorized(requestIfNeeded: Bool) async throws -> Bool { calls += 1; return false }
        func schedule(identifier: String) async throws { calls += 1 }
        func remove(identifiers: [String]) { calls += 1 }
    }

    private let fixtureDate = Date(timeIntervalSince1970: 1_700_049_600)
    private let precisionMidnight: TimeInterval = 800_064_000 // UTC2026-05-10, measured from2001-01-01.
    private func profileFixture() -> UserProfile {
        UserProfile(name: "Recovery fixture", age: 34, gender: .other, heightCm: 172.5,
            currentWeightKg: 73.25, goalWeightKg: 72, experienceLevel: .intermediate,
            primaryGoal: .generalHealth, workoutDaysPerWeek: 3, equipmentAccess: .minimal,
            dietaryPreferences: [.highProtein], injuriesOrLimitations: "Keep original wording")
    }
    private func populateEveryModel(_ context: ModelContext, photoBytes: Int) throws {
        let owner = profileFixture()
        owner.createdAt = Date(timeIntervalSinceReferenceDate: precisionMidnight.nextDown)
        owner.updatedAt = Date(timeIntervalSinceReferenceDate: precisionMidnight.nextUp)
        context.insert(owner)
        context.insert(Item(timestamp: fixtureDate, title: "Idea", note: "Keep", isPinned: true, isComplete: true, accentName: "blue"))
        context.insert(BodyMetric(date: fixtureDate, weightKg: 73.25, bodyFatPercentage: 18, chestCm: 96,
            waistCm: 82, hipsCm: 94, armsCm: 33, thighsCm: 53, notes: "Metric note"))
        let health = HealthSnapshot(date: fixtureDate); health.owner = owner
        health.restingHeartRate = 60; health.heartRateVariability = 50; health.sleepHours = 7.5
        health.activeEnergyBurned = 450; health.exerciseMinutes = 35; health.energyLevel = 7
        health.sorenessLevel = 3; health.mood = .good; health.notes = "Historic snapshot"
        context.insert(health)
        let milestone = Milestone(title: "Milestone", description: "Stored detail", category: .consistency)
        milestone.owner = owner; milestone.achievedDate = fixtureDate; milestone.isAchieved = true; context.insert(milestone)
        let photo = ProgressPhoto(date: fixtureDate, photoData: try patternPhoto(minimumBytes: photoBytes, seed: 71), weightAtTime: 73.25, notes: "Photo note")
        photo.owner = owner; context.insert(photo)
        let streak = Streak(type: .checkIn); streak.owner = owner; streak.currentStreak = 2; streak.longestStreak = 5; streak.lastCheckIn = fixtureDate
        context.insert(streak)
        let meal = MealLog(date: fixtureDate, mealName: "Meal العربية", calories: 540, protein: 1e300,
            carbs: 60, fat: 12, notes: "Meal note العربية", photoData: try patternPhoto(minimumBytes: photoBytes, seed: 23))
        meal.owner = owner; context.insert(meal)
        let checkIn = DailyCheckIn(date: fixtureDate, energyLevel: 7, sorenessLevel: 3, sleepQuality: 8,
            stressLevel: 4, mood: .good, journalNote: "Check-in note", didTrain: true)
        checkIn.owner = owner; context.insert(checkIn)
        let workout = WorkoutLog(date: fixtureDate, workoutName: "Recorded workout",
            exercises: [LoggedExercise(name: "Squat", sets: [LoggedSet(reps: 8, weight: 25.5, rpe: 7)])],
            perceivedExertion: 7, notes: "Workout note", durationMinutes: 45)
        workout.owner = owner; context.insert(workout)
        let journal = JournalEntry(date: fixtureDate, title: "Entry", content: "Stored content العربية", mood: .okay, tags: ["tag", "وسم"])
        journal.owner = owner; context.insert(journal)
        let memory = CoachMemoryEntry(type: .reflection, content: "Unverified earlier coaching note")
        memory.date = fixtureDate; context.insert(memory)
        let goal = Goal(name: "Own goal", currentValue: 2.5, targetValue: 10, unit: "sessions", category: "general")
        goal.owner = owner; goal.lastAdjustedByCoach = Date(timeIntervalSinceReferenceDate: precisionMidnight.nextDown)
        goal.adjustmentNotes = "Earlier saved note"; context.insert(goal)
        let habit = Habit(name: "Own habit", coachSuggested: true)
        habit.createdAt = fixtureDate; habit.isActive = true; habit.currentStreak = 2; habit.bestStreak = 7
        habit.totalCompletions = 4; habit.lastCompletedDate = fixtureDate.addingTimeInterval(-86_400)
        habit.coachNotes = "General idea"; habit.targetFrequencyPerWeek = 4
        habit.toggleCompletion(now: fixtureDate); context.insert(habit)
        try context.save()
    }
    private func patternPhoto(minimumBytes: Int, seed: UInt32) throws -> Data {
        // Real, lossless, deterministic image bytes rather than non-image data
        // placed in a photo field. Noise avoids accidental tiny compressed files.
        let side = max(16, Int(ceil(sqrt(Double(minimumBytes) / 3))) + 8)
        var pixels = Data(count: side * side * 3)
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var state = seed
            for index in bytes.indices {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5
                bytes[index] = UInt8(truncatingIfNeeded: state)
            }
        }
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(width: side, height: side, bitsPerComponent: 8,
            bitsPerPixel: 24, bytesPerRow: side * 3, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return result as Data
    }
    private func hash(_ url: URL) throws -> SHA256.Digest { SHA256.hash(data: try Data(contentsOf: url)) }

    @MainActor private final class RecoveryFixture {
        let directory: URL
        let url: URL
        let container: ModelContainer
        var context: ModelContext { container.mainContext }
        let model: LuminaViewModel
        init(name: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-Recovery-" + name + "-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            url = directory.appendingPathComponent("journal.sqlite")
            let schema = Schema(LuminaApp.modelTypes)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            model = LuminaViewModel(modelContext: container.mainContext)
        }
        func open(_ url: URL, allowsSave: Bool) throws -> ModelContainer {
            let schema = Schema(LuminaApp.modelTypes)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none)])
        }
        func remove() { withExtendedLifetime(container) {}; try? FileManager.default.removeItem(at: directory) }
    }

    nonisolated private final class SQLFixture {
        private(set) var handle: OpaquePointer?
        init(url: URL, writable: Bool = true) throws {
            let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
            guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else { throw JournalTransferError.unavailable }
        }
        deinit { close() }
        func close() { if let handle { sqlite3_close(handle); self.handle = nil } }
        func exec(_ sql: String) throws { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw JournalTransferError.invalid } }
        func integer(_ sql: String) throws -> Int64 {
            var query: OpaquePointer?; defer { sqlite3_finalize(query) }
            guard sqlite3_prepare_v2(handle, sql, -1, &query, nil) == SQLITE_OK, sqlite3_step(query) == SQLITE_ROW else { throw JournalTransferError.invalid }
            return sqlite3_column_int64(query, 0)
        }
        func text(_ sql: String) throws -> String {
            var query: OpaquePointer?; defer { sqlite3_finalize(query) }
            guard sqlite3_prepare_v2(handle, sql, -1, &query, nil) == SQLITE_OK, sqlite3_step(query) == SQLITE_ROW,
                  let text = sqlite3_column_text(query, 0) else { throw JournalTransferError.invalid }
            return String(cString: text)
        }
    }
}
