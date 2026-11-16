import SwiftUI
import Foundation
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @State private var backup: DatabaseBackup?
    @State private var exporting = false
    @State private var confirmingDeletion = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Reminders") {
                Toggle("Weekly journal reminder", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task {
                            if enabled {
                                await viewModel.requestNotificationPermission()
                                remindersEnabled = viewModel.notificationsAuthorized
                                await viewModel.scheduleProactiveCoachNotifications()
                            } else {
                                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                            }
                        }
                    }
                Text("If permission is denied, enable notifications in iOS Settings.")
            }
            Section("Your data") {
                Button("Export database backup") {
                    do {
                        backup = DatabaseBackup(data: try viewModel.exportDatabase())
                        exporting = true
                    } catch { message = "Export failed: \(error.localizedDescription)" }
                }
                Text("Exports the stored records and photos as a SQLite database. In-app restore is not available. Keep the backup private.")
                    .font(.caption)
                Button("Health permissions") {
                    Task {
                        await viewModel.requestHealthKitAccess()
                    }
                }
                Button("Delete all local data", role: .destructive) { confirmingDeletion = true }
                    .accessibilityIdentifier("lumina.delete.request")
                Text("Earlier prototype versions added sample records. Lumina cannot identify them reliably, so existing entries are preserved until you choose to remove them.")
                    .font(.caption)
            }
            Section("About") {
                Text("Offline coaching uses general suggestions. It does not inspect photos, measure habit effects or calculate health scores.")
                NavigationLink("Privacy and your data") {
                    LuminaPrivacyInfoView()
                }
                .accessibilityIdentifier("lumina.privacy")
            }
        }
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: backup, contentType: .database,
                      defaultFilename: "Lumina-backup.sqlite") { result in
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                message = "Export failed: \(error.localizedDescription)"
            }
            backup = nil
        }
        .confirmationDialog("Delete all local Lumina records and photos?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete all local data", role: .destructive) {
                do {
                    try viewModel.deleteAllLocalRecords()
                    remindersEnabled = false
                    if !LuminaApp.isUIQA { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
                } catch { message = "Deletion failed: \(error.localizedDescription)" }
            }
            .accessibilityIdentifier("lumina.delete.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Export a backup first if you want to keep a copy. Exported backups and records in Apple Health are not deleted.")
        }
        .alert("Lumina", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}

private struct LuminaPrivacyInfoView: View {
    var body: some View {
        Form {
            Section("Your journal") {
                Text("Your saved records may include profile details, goals, workouts, meals, check-ins, habits, journal text, photos, body measurements, health snapshots and coaching notes.")
                Text("Earlier prototype versions added sample records. Existing entries are preserved because Lumina cannot reliably distinguish samples from records you supplied. Review their dates and contents before treating them as measurements.")
            }
            Section("Storage and offline processing") {
                Text("Lumina stores its journal in its protected app storage, including storage shared with its own extensions where configured. This version disables automatic CloudKit database sync and requests to the cloud coaching service.")
                Text("Offline coaching offers general local suggestions. It does not inspect photos, calculate validated health scores or establish a habit's effects.")
                Text("These settings do not disable iOS device backups or destinations you choose when exporting. Apple or another storage provider may hold copies according to your device, account and destination settings.")
            }
            Section("Photos and permissions") {
                Text("The system photo picker lets you select an image to copy into Lumina. This version does not offer camera capture or voice-note recording through its supported screens.")
                Text("Apple Health access is unavailable in this build. Previously stored health snapshots remain in your journal until you delete them. Lumina does not write or delete Apple Health records.")
                Text("Weekly reminders are optional and require notification permission. You can turn off reminders in Lumina or notifications in iOS Settings.")
            }
            Section("Exporting records") {
                Text("Export database backup creates a SQLite file containing stored records and photo copies. You choose its destination using the system file picker. The app does not automatically send the backup to the developer.")
                Text("Keep backups private: someone who can open the exported file may be able to read its contents. In-app restore is not available in this version.")
            }
            Section("Retention and deletion") {
                Text("Journal records remain until you remove them. Delete all local data asks for confirmation before removing local journal records, saved photo copies and current coaching/session caches. Dismissing the confirmation keeps the records.")
                Text("Local deletion does not remove exported files, device-backup copies, original photos in your Photos library or Apple Health records. Manage those copies through the relevant system or provider.")
            }
        }
        .navigationTitle("Privacy and your data")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("lumina.privacy.screen")
    }
}
