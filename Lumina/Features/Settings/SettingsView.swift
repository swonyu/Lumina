import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var message: String?
    // Keep operation state outside the language-specific Form cells.
    @State private var journalTransfer = JournalTransferController()

    private var reminders: WeeklyReminderCoordinator {
        viewModel.weeklyReminders ?? LuminaApp.weeklyReminders
    }

    var body: some View {
        Form {
            // Keep the single privacy route immediately reachable even when
            // larger text makes the explanatory settings rows several screens tall.
            Section {
                NavigationLink(L("Privacy and your data")) {
                    LuminaPrivacyInfoView()
                }
                .accessibilityIdentifier("lumina.privacy")
            }
            Section(L("Reminders")) {
                Toggle(L("Weekly journal reminder"), isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { _ = reminders.setEnabled($0) }))
                    .accessibilityIdentifier("lumina.reminders.enabled")
                if reminders.isUpdating {
                    ProgressView(L("Updating the reminder…"))
                }
                Text(L("Optional. A reminder to review your journal on Sundays at 7 pm. Turning it off cancels the pending reminder."))
                if let error = reminders.errorMessage {
                    Text(L(error)).foregroundStyle(.primary)
                        .accessibilityIdentifier("lumina.reminders.error")
                }
            }
            Section(L("Your data")) {
                JournalRecoveryControls(controller: journalTransfer)
                Button(L("Apple Health information")) {
                    Task {
                        await viewModel.requestHealthKitAccess()
                    }
                }
                Button(L("Delete all local data"), role: .destructive) { confirmingDeletion = true }
                    .disabled(journalTransfer.blocksJournalDeletion)
                    .accessibilityIdentifier("lumina.delete.request")
                Text(L("Earlier prototype versions added sample records. Lumina cannot identify them reliably, so existing entries are preserved until you choose to remove them."))
                    .font(.caption)
            }
            Section(L("About")) {
                Text(L("Coach uses Apple’s on-device model when available, or clearly labeled local guidance. Replies can be inaccurate. Photos are not attached to model requests. Coaching is not a validated health measurement or evidence of a habit’s effects."))
            }
            Section(L("Language")) {
                Picker(L("App language"), selection: Binding(
                    get: { LocalizationManager.shared.currentLanguage },
                    set: { language in
                        guard language != LocalizationManager.shared.currentLanguage else { return }
                        LocalizationManager.shared.setLanguage(language)
                        if reminders.isEnabled {
                            // Refresh the already-authorized local reminder's wording.
                            // This never requests permission because language changed.
                            _ = reminders.setEnabled(true, requestIfNeeded: false)
                        }
                    })) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("lumina.language-picker")
                Text(L("App text updates immediately. Saved entries and earlier coaching replies keep their original wording. System dialogs may follow iOS language settings."))
                    .font(.caption)
            }
        }
        // A UIKit-backed Form can retain mirrored cell transforms when its
        // layout direction changes in place. Recreate this Form's cells only;
        // Settings state, navigation, the model and other tabs retain identity.
        .id(LocalizationManager.shared.currentLanguage)
        .navigationTitle(L("Settings"))
        // UIKit retained the previous direction's native Back glyph after a
        // live switch. Refresh only this item; navigation and drafts keep identity.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: LocalizationManager.shared.currentLanguage == .arabic
                          ? "chevron.right" : "chevron.left")
                        .environment(\.layoutDirection, .leftToRight)
                        .flipsForRightToLeftLayoutDirection(false)
                }
                .accessibilityLabel(L("Back to Home"))
                .accessibilityIdentifier("Lumina")
                .id(LocalizationManager.shared.currentLanguage)
            }
        }
        .modifier(JournalTransferPresentations(controller: journalTransfer))
        .confirmationDialog(L("Delete all local Lumina records and photos?"), isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(L("Delete all local data"), role: .destructive) {
                do {
                    try viewModel.deleteAllLocalRecords()
                } catch let error as JournalTransferError { message = L(error.messageKey) }
                catch { message = L("Deletion failed: %@", error.localizedDescription) }
            }
            .disabled(journalTransfer.blocksJournalDeletion)
            .accessibilityIdentifier("lumina.delete.confirm")
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This cannot be undone. Export a backup first if you want to keep a copy. Exported backups and records in Apple Health are not deleted."))
        }
        .alert(L("Lumina"), isPresented: Binding(
            get: { message != nil || reminders.errorMessage != nil },
            set: { if !$0 { message = nil; reminders.errorMessage = nil } })) {
            Button(L("OK")) { message = nil; reminders.errorMessage = nil }
        } message: { Text(L(message ?? reminders.errorMessage ?? "")) }
        .onDisappear { journalTransfer.leavingScreen() }
    }
}

private struct LuminaPrivacyInfoView: View {
    var body: some View {
        Form {
            Section(L("Your journal")) {
                Text(L("Your saved records may include profile details, goals, workouts, meals, check-ins, habits, journal text, photos, body measurements, health snapshots and coaching notes."))
                Text(L("Earlier prototype versions added sample records. Existing entries are preserved because Lumina cannot reliably distinguish samples from records you supplied. Review their dates and contents before treating them as measurements."))
            }
            Section(L("Storage and offline processing")) {
                Text(L("Lumina stores its journal in its protected app storage, including storage shared with its own extensions where configured. This version disables automatic CloudKit database sync and requests to the cloud coaching service."))
                Text(L("Photos are not attached to model requests. Replies can be inaccurate and are not intended for diagnosis, validated health measurement or determining a habit’s effects."))
                Text(L("These settings do not disable iOS device backups or destinations you choose when exporting. Apple or another storage provider may hold copies according to your device, account and destination settings."))
            }
            Section(L("On-device coaching")) {
                Text(L("When Apple’s system language model is already available and supports the selected app language, Coach uses your question, a limited summary of saved records and recent conversation excerpts on your device. Incomplete context is marked. The app does not attach photos or unverified historic AI notes, or read saved provider credentials for the request."))
                Text(L("What you type is part of the request. Do not enter passwords or other secrets. The app makes no requests to a cloud AI provider and requires no API key or manual model download. When the model is unavailable, busy or too slow, replies may use clearly labeled local rules instead."))
                Text(L("Use Stop to cancel a reply. Leaving Coach or putting the app in the background also cancels the current request. Model replies can be inaccurate and do not automatically change your records."))
            }
            Section(L("Photos and permissions")) {
                Text(L("The system photo picker lets you select an image to copy into Lumina. This version does not offer camera capture or voice-note recording through its supported screens."))
                Text(L("Apple Health access is unavailable in this build. Previously stored health snapshots remain in your journal until you delete them. Lumina does not write or delete Apple Health records."))
                Text(L("Weekly reminders are optional and require notification permission. You can turn off reminders in Lumina or notifications in iOS Settings."))
            }
            Section(L("Exporting records")) {
                Text(L("Export database backup creates a SQLite snapshot of stored records and photo copies. Supported new backups can be previewed and restored into an empty journal. You choose the file destination. The app does not automatically send backups to the developer."))
                Text(L("Keep backups private: someone who can open the exported file may be able to read its contents. Supported backups can be previewed and restored into an empty local journal. Raw recovery copies and older database exports cannot be imported by this version. Exporting never removes or reduces saved photos."))
            }
            Section(L("Retention and deletion")) {
                Text(L("Journal records remain until you remove them. Delete all local data asks for confirmation before removing local journal records, saved photo copies and current coaching/session caches. Dismissing the confirmation keeps the records."))
                Text(L("Local deletion does not remove exported files, device-backup copies, original photos in your Photos library or Apple Health records. Manage those copies through the relevant system or provider."))
                Text(L("There is no Lumina account to delete. Local deletion does not close your Apple or storage-provider accounts."))
            }
        }
        .navigationTitle(L("Privacy and your data"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("lumina.privacy.screen")
    }
}
