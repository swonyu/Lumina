import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(LuminaViewModel.self) private var viewModel
    
    @State private var notificationsEnabled = true
    @State private var aiEmotionalSupport = true
    @State private var weeklyReports = true
    @State private var darkMode = true
    
    @State private var showExportAlert = false
    @State private var showHealthAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("settings.preferences"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Toggle("Proactive Coach Notifications", isOn: $notificationsEnabled)
                            .onAppear {
                                notificationsEnabled = viewModel.notificationsAuthorized
                            }
                            .onChange(of: notificationsEnabled) { _, newValue in
                                Task {
                                    if newValue {
                                        await viewModel.requestNotificationPermission()
                                        await viewModel.scheduleProactiveCoachNotifications()
                                    } else {
                                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                                    }
                                }
                            }
                        Toggle(L("settings.ai_emotional_support"), isOn: $aiEmotionalSupport)
                        Toggle(L("settings.weekly_reports"), isOn: $weeklyReports)
                        Toggle(L("settings.dark_mode"), isOn: $darkMode)
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("settings.data_privacy"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        NavigationLink {
                            CoachMemoryInsightsView()
                        } label: {
                            Label("Coach Memory & Understanding", systemImage: "brain.head.profile")
                        }
                        
                        // Round 86/89/90 polish: actionable limited-impact nudge in Settings (navigates to Coach Memory)
                        if viewModel.hasLimitedCoachHabitImpact {
                            NavigationLink {
                                CoachMemoryInsightsView()
                            } label: {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.yellow)
                                    Text("Coach noted limited impact on some suggested habits — review in Coach Memory.")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(.top, 4)
                        }

                        NavigationLink {
                            VoiceNotesView()
                        } label: {
                            Label("Voice Notes to Coach", systemImage: "mic")
                        }
                        
                        Button(L("settings.export_data")) { showExportAlert = true }
                        Button(L("settings.health_permissions")) { showHealthAlert = true }
                        Button(L("settings.delete_all_data"), role: .destructive) {
                            print("Delete all data tapped (demo)")
                        }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("settings.about"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(L("settings.version_full"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle(L("settings.title"))
        .withAppLanguage()
        .alert(L("settings.export_data"), isPresented: $showExportAlert) {
            Button(L("general.ok")) {}
        } message: {
            Text(L("settings.export_data"))
        }
        .alert(L("settings.health_permissions"), isPresented: $showHealthAlert) {
            Button(L("general.ok")) {}
        } message: {
            Text(L("settings.health_permissions"))
        }
    }
}
