import Foundation
import Observation

/// Owns one pending import. A replaced, canceled or obsolete request cannot
/// publish bytes or invoke its save callback, even if its loader ignores cancellation.
@MainActor
@Observable
final class LocalPhotoImport {
    private(set) var data: Data?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    @discardableResult
    func load(
        using loader: @escaping @MainActor () async throws -> Data?,
        isCurrentSession: @escaping @MainActor () -> Bool,
        onLoaded: @escaping @MainActor (Data) -> Void = { _ in }
    ) -> Task<Void, Never> {
        clear()
        let id = UUID()
        requestID = id
        isLoading = true

        let task = Task { [weak self] in
            do {
                guard let bytes = try await loader(), !bytes.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                guard isCurrentSession() else {
                    self.clear()
                    return
                }
                // A Photos provider returning nonempty bytes does not establish
                // a usable image. Validate before publishing or saving, using
                // the same bounded, original-byte-preserving recovery policy.
                // Image decoding stays off the main actor; navigation remains
                // responsive and cancellation reaches the validation worker.
                let budget = JournalTransferBudget(seconds: 15)
                let validation = Task.detached(priority: .userInitiated) {
                    try JournalRecoveryRecord.validatePhoto(bytes, limits: .standard, budget: budget)
                }
                try await withTaskCancellationHandler {
                    try await validation.value
                } onCancel: {
                    budget.cancel()
                    validation.cancel()
                }
                // Another selection, deletion or navigation can occur during
                // the background validation; repeat the actual publication gate.
                guard self.requestID == id, !Task.isCancelled else { return }
                guard isCurrentSession() else {
                    self.clear()
                    return
                }
                self.data = bytes
                self.isLoading = false
                self.pendingTask = nil
                onLoaded(bytes)
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                guard isCurrentSession() else {
                    self.clear()
                    return
                }
                self.isLoading = false
                self.pendingTask = nil
                self.errorMessage = L("Could not load the selected photo. Choose another image or remove the selection.")
            }
        }
        pendingTask = task
        return task
    }

    /// Preserve a completed draft photo when leaving the screen, but invalidate
    /// a pending operation so it cannot change that draft after navigation.
    func cancelPending() {
        guard isLoading else { return }
        pendingTask?.cancel()
        pendingTask = nil
        requestID = nil
        isLoading = false
        errorMessage = L("Photo import was canceled. Choose the photo again or remove the selection.")
    }

    func clear() {
        pendingTask?.cancel()
        pendingTask = nil
        requestID = nil
        data = nil
        isLoading = false
        errorMessage = nil
    }
}
