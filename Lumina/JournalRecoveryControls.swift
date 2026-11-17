import SwiftUI
import SwiftData
import Observation
import UniformTypeIdentifiers

/// Shared across screen lifetimes. Leaving and re-entering Settings cannot
/// start another file worker while a canceled provider operation is finishing.
@MainActor
@Observable
final class JournalTransferAdmission {
    static let shared = JournalTransferAdmission()
    private var owner: UUID?
    var isBusy: Bool { owner != nil }
    func owns(_ token: UUID) -> Bool { owner == token }
    func acquire() -> UUID? {
        guard owner == nil else { return nil }
        let token = UUID(); owner = token; return token
    }
    func release(_ token: UUID) {
        guard owner == token else { return }
        owner = nil
    }
}

@MainActor
@Observable
final class JournalTransferController {
    var exporting = false
    var importing = false
    var exportFile: JournalExportFile?
    var preview: JournalRecoveryPreview?
    private(set) var isWorking = false
    private(set) var isCommitting = false
    private(set) var workLabel = "Preparing database backup…"
    private(set) var errorKey: String?
    private(set) var restoredCount: Int?
    private(set) var canOfferRawCopy = false
    private(set) var exportFilename = "Lumina-backup.sqlite"
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var ownedExport: OwnedJournalFile?
    @ObservationIgnored private var ownedRestore: OwnedJournalFile?
    @ObservationIgnored private let admission: JournalTransferAdmission
    @ObservationIgnored private let exporter: @MainActor (LuminaViewModel) async throws -> OwnedJournalFile
    @ObservationIgnored private let rawExporter: @MainActor (LuminaViewModel) async throws -> OwnedJournalFile
    @ObservationIgnored private var lease: UUID?

    var blocksJournalDeletion: Bool { admission.isBusy || exporting || importing || preview != nil }

    init() {
        admission = .shared
        exporter = { model in try await model.prepareDatabaseBackup() }
        rawExporter = { model in try await model.prepareRawDatabaseBackup() }
    }
    init(admission: JournalTransferAdmission,
         exporter: @escaping @MainActor (LuminaViewModel) async throws -> OwnedJournalFile) {
        self.admission = admission; self.exporter = exporter
        rawExporter = { model in try await model.prepareRawDatabaseBackup() }
    }
    init(admission: JournalTransferAdmission,
         exporter: @escaping @MainActor (LuminaViewModel) async throws -> OwnedJournalFile,
         rawExporter: @escaping @MainActor (LuminaViewModel) async throws -> OwnedJournalFile) {
        self.admission = admission; self.exporter = exporter; self.rawExporter = rawExporter
    }

    isolated deinit {
        // Running tasks retain this controller until real worker termination.
        // A discarded presentation must not leave its private copy or lease.
        ownedExport?.remove(); ownedRestore?.remove()
        if let lease { admission.release(lease) }
    }

    private func acquirePreparation() -> UUID? {
        guard let token = admission.acquire() else {
            errorKey = "Another backup operation is finishing. Wait for it to stop before trying again."
            return nil
        }
        lease = token
        return token
    }

    private func releaseAdmissionIfIdle() {
        guard task == nil, ownedExport == nil, ownedRestore == nil, let lease else { return }
        admission.release(lease); self.lease = nil
    }

    private func finishedWork() {
        isCommitting = false; isWorking = false; task = nil
        releaseAdmissionIfIdle()
    }

    func beginExport(using model: LuminaViewModel) {
        beginExport(using: model, raw: false)
    }

    func beginRawExport(using model: LuminaViewModel) {
        guard canOfferRawCopy else { return }
        beginExport(using: model, raw: true)
    }

    private func beginExport(using model: LuminaViewModel, raw: Bool) {
        guard task == nil, ownedExport == nil, ownedRestore == nil else { return }
        guard acquirePreparation() != nil else { return }
        isWorking = true; workLabel = "Preparing database backup…"; errorKey = nil; restoredCount = nil
        canOfferRawCopy = false
        exportFilename = raw ? "Lumina-raw-recovery.sqlite" : "Lumina-backup.sqlite"
        task = Task {
            defer { finishedWork() }
            do {
                let file: OwnedJournalFile
                if raw { file = try await rawExporter(model) }
                else { file = try await exporter(model) }
                if Task.isCancelled { file.remove(); throw CancellationError() }
                ownedExport = file; exportFile = JournalExportFile(file: file.file); exporting = true
                canOfferRawCopy = raw
            } catch {
                record(error)
                canOfferRawCopy = raw || (error as? JournalTransferError) == .rawRecoveryAvailable
            }
        }
    }

    func chooseRestore() {
        guard task == nil, ownedExport == nil, ownedRestore == nil else { return }
        errorKey = nil; restoredCount = nil
        guard !admission.isBusy else {
            errorKey = "Another backup operation is finishing. Wait for it to stop before trying again."
            return
        }
        // Inspecting a file never changes the current journal. Users can check
        // a backup before deciding what to do with their existing records.
        importing = true
    }

    func restoreRestriction(using model: LuminaViewModel) -> String? {
        do {
            guard model.modelContext.container.configurations.allSatisfy(\.allowsSave) else { throw JournalTransferError.readOnly }
            guard !model.modelContext.hasChanges, model.dataRevision == 0 else { throw JournalTransferError.changed }
            guard try !model.journalHasRecords() else { throw JournalTransferError.nonempty }
            return nil
        } catch { return (error as? JournalTransferError ?? .unavailable).messageKey }
    }

    func selectedRestoreFile(_ file: URL) {
        guard task == nil, ownedExport == nil, ownedRestore == nil else { return }
        guard acquirePreparation() != nil else { return }
        isWorking = true; workLabel = "Checking the selected backup…"; errorKey = nil
        task = Task {
            defer { finishedWork() }
            do {
                let result = try await JournalRecoveryIO.prepareRestore(selected: file)
                if Task.isCancelled { result.owned.remove(); throw CancellationError() }
                ownedRestore = result.owned; preview = result
            } catch { record(error) }
        }
    }

    func restore(using model: LuminaViewModel) {
        guard task == nil, let preview else { return }
        guard let lease, admission.owns(lease) else { record(JournalTransferError.unavailable); return }
        isWorking = true; isCommitting = true; workLabel = "Restoring records…"; errorKey = nil
        task = Task {
            defer { finishedWork() }
            // Let the progress state render before the bounded atomic import.
            await Task.yield()
            do {
                try Task.checkCancellation()
                try model.restoreJournal(preview)
                restoredCount = preview.records.count
                self.preview = nil; ownedRestore?.remove(); ownedRestore = nil
                await model.bootstrapAfterLaunch()
            } catch { record(error) }
        }
    }

    func cancelPreparation() {
        guard !isCommitting else { return }
        task?.cancel()
        // Admission remains closed until the actual worker has returned and
        // removed its staging directory. Repeated taps cannot overlap work.
        if task != nil { workLabel = "Canceling preparation…" }
    }

    func finishedExport(_ result: Result<URL, Error>? = nil) {
        if case .failure(let error) = result { record(error) }
        exporting = false; exportFile = nil; ownedExport?.remove(); ownedExport = nil
        releaseAdmissionIfIdle()
    }

    func dismissPreview() {
        guard !isCommitting else { return }
        preview = nil; ownedRestore?.remove(); ownedRestore = nil
        releaseAdmissionIfIdle()
    }

    func leavingScreen() {
        cancelPreparation()
        if !exporting { finishedExport() }
        if preview == nil { ownedRestore?.remove(); ownedRestore = nil }
        releaseAdmissionIfIdle()
    }

    func record(_ error: Error) {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { return }
        errorKey = (error as? JournalTransferError ?? .unavailable).messageKey
    }
}

struct JournalRecoveryControls: View {
    @Environment(LuminaViewModel.self) private var viewModel
    let controller: JournalTransferController

    var body: some View {
        @Bindable var controller = controller
        Group {
            Button(L("Export database backup")) { controller.beginExport(using: viewModel) }
                .disabled(controller.isWorking)
                .accessibilityIdentifier("lumina.backup.export")
            Button(L("Restore a database backup")) { controller.chooseRestore() }
                .disabled(controller.isWorking)
                .accessibilityIdentifier("lumina.restore.choose")
#if UI_TESTING
            if LuminaApp.isUIQA && ProcessInfo.processInfo.arguments.contains("--lumina-qa-recovery-fixture") {
                Button("Use isolated recovery QA fixture") { controller.prepareQARecoveryFixture(using: viewModel) }
                    .disabled(controller.isWorking)
                    .accessibilityIdentifier("lumina.restore.qa-fixture")
            }
#endif
            Text(L("Supported backups include a restorable journal snapshot. Restore requires an empty local journal and a final confirmation. Raw recovery copies and older database exports cannot be restored in this version. Keep every backup private."))
                .font(.caption)
            if controller.isWorking {
                ProgressView(L(controller.workLabel))
                    .accessibilityIdentifier("lumina.backup.progress")
                if !controller.isCommitting {
                    Button(L("Cancel preparation")) { controller.cancelPreparation() }
                        .accessibilityIdentifier("lumina.backup.cancel")
                }
            }
            if let error = controller.errorKey {
                Label(L(error), systemImage: "exclamationmark.circle")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lumina.backup.error")
            }
            if controller.canOfferRawCopy {
                Button(L("Export raw recovery copy")) { controller.beginRawExport(using: viewModel) }
                    .disabled(controller.isWorking)
                    .accessibilityIdentifier("lumina.backup.raw-export")
                Text(L("A raw recovery copy preserves the stored database within the file-size limit. This version cannot restore it. It does not remove or reduce your saved photos. Keep this file private."))
                    .font(.caption)
            }
            if let count = controller.restoredCount {
                Label(L("Restored %d records.", count), systemImage: "checkmark.circle")
                    .accessibilityIdentifier("lumina.restore.success")
            }
        }
    }
}

/// Presenters retain their identity when Settings rebuilds only its Form cells.
struct JournalTransferPresentations: ViewModifier {
    @Environment(LuminaViewModel.self) private var viewModel
    let controller: JournalTransferController

    func body(content: Content) -> some View {
        @Bindable var controller = controller
        content
        .fileExporter(isPresented: $controller.exporting, item: controller.exportFile,
                      contentTypes: [.database], defaultFilename: controller.exportFilename) { result in
            controller.finishedExport(result)
        } onCancellation: {
            controller.finishedExport()
        }
        .fileImporter(isPresented: $controller.importing, allowedContentTypes: [.database, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let files):
                guard files.count == 1, let file = files.first else { controller.record(JournalTransferError.invalid); return }
                controller.selectedRestoreFile(file)
            case .failure(let error): controller.record(error)
            }
        }
        .sheet(item: $controller.preview, onDismiss: { controller.dismissPreview() }) { preview in
            let restriction = controller.restoreRestriction(using: viewModel)
            NavigationStack {
                Form {
                    if let restriction {
                        Section {
                            Text(L("Previewing this backup does not change your existing records. You do not need to delete anything to inspect it."))
                            Text(L(restriction))
                                .accessibilityIdentifier("lumina.restore.blocked")
                        }
                    }
                    Section(L("Backup preview")) {
                        Text(L("Created: %@", preview.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(LocalizationManager.shared.currentLanguage.locale))))
                        Text(L("Records: %d", preview.records.count))
                        Text(L("Saved photo data: %.1f MiB", Double(preview.photoBytes) / 1_048_576))
                        ForEach(JournalRecordKind.allCases.filter { preview.counts[$0, default: 0] > 0 }, id: \.self) { kind in
                            LabeledContent(L(kind.labelKey), value: String(preview.counts[kind, default: 0]))
                        }
                    }
                    Section {
                        Text(L("Restore adds these records and saved photo copies to this empty journal. It does not import language, reminder or provider-account settings. It does not write to Apple Health or alter originals in Photos. Saved notes keep their original wording; review their dates and claims."))
                        Text(L("Supported limits: 512 MiB per file, 10,000 records, 16 MiB per photo, 128 MiB of photo data and 64 MiB of record data. Photos must be readable and contain at most 64 million pixels across their frames. Large or slow files may be refused. No paid service or account is needed."))
                            .font(.caption)
                    }
                    if let error = controller.errorKey {
                        Label(L(error), systemImage: "exclamationmark.circle")
                            .accessibilityIdentifier("lumina.restore.preview-error")
                    }
                    if controller.isCommitting { ProgressView(L("Restoring records…")) }
                }
                .navigationTitle(L("Restore journal"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Cancel")) { controller.dismissPreview() }
                            .disabled(controller.isCommitting)
                            .accessibilityIdentifier("lumina.restore.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Restore records")) { controller.restore(using: viewModel) }
                            .disabled(controller.isWorking || preview.records.isEmpty || restriction != nil)
                            .accessibilityIdentifier("lumina.restore.confirm")
                    }
                }
                .interactiveDismissDisabled(controller.isCommitting)
                .accessibilityIdentifier("lumina.restore.preview")
                .withAppLanguage()
            }
        }
    }
}

#if UI_TESTING
extension JournalTransferController {
    /// UI QA supplies a file URL at the picker boundary. The real export,
    /// selected-file copy, untrusted reader, preview and atomic import remain
    /// unchanged. This never writes directly to the destination journal.
    fileprivate func prepareQARecoveryFixture(using model: LuminaViewModel) {
        guard LuminaApp.isUIQA, ProcessInfo.processInfo.arguments.contains("--lumina-qa-recovery-fixture"),
              task == nil, ownedExport == nil, ownedRestore == nil else { return }
        guard acquirePreparation() != nil else { return }
        isWorking = true; workLabel = "Checking the selected backup…"; errorKey = nil
        task = Task {
            defer { finishedWork() }
            do {
                let file = try await QARecoveryFixture.makeExport()
                defer { file.remove() }
                let result = try await JournalRecoveryIO.prepareRestore(selected: file.file)
                if Task.isCancelled { result.owned.remove(); throw CancellationError() }
                ownedRestore = result.owned; preview = result
            } catch { record(error) }
        }
    }
}

@MainActor
private enum QARecoveryFixture {
    static func makeExport() async throws -> OwnedJournalFile {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-QA-Recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(LuminaApp.modelTypes)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("fixture.sqlite"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(MealLog(mealName: "Recovery fixture meal", protein: 42, notes: "Reviewable recovery fixture note"))
        context.insert(Habit(name: "Recovery fixture habit"))
        try context.save()
        return try await LuminaViewModel(modelContext: context).prepareDatabaseBackup()
    }
}
#endif
