import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var aiEmotionalSupport = true
    @State private var weeklyReports = true
    @State private var darkMode = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Preferences")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Toggle("Daily Reminders", isOn: $notificationsEnabled)
                        Toggle("AI Emotional Support", isOn: $aiEmotionalSupport)
                        Toggle("Weekly AI Reports", isOn: $weeklyReports)
                        Toggle("Dark Glass Mode", isOn: $darkMode)
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Data & Privacy")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Button("Export My Data") { /* TODO */ }
                        Button("Manage Apple Health Permissions") { /* TODO */ }
                        Button("Delete All Data", role: .destructive) {
                            // Simple destructive action for dev/testing
                            // In real app this would show stronger confirmation + wipe SwiftData + HealthKit
                            print("Delete all data tapped (demo)")
                        }
                    }
                }
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Lumina")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Version 0.1 • Built with ❤️ and a lot of glassy materials")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding()
        }
        .glassBackground()
        .navigationTitle("Settings")
    }
}
