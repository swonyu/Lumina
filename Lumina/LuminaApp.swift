//
//  LuminaApp.swift
//  Lumina
//
//  Created by saleh alayed on 10/12/1447 AH.
//

import SwiftUI
import SwiftData

@main
struct LuminaApp: App {
    static let modelTypes: [any PersistentModel.Type] = [
            Item.self,
            UserProfile.self,
            BodyMetric.self,
            HealthSnapshot.self,
            Milestone.self,
            ProgressPhoto.self,
            Streak.self,
            MealLog.self,
            DailyCheckIn.self,
            WorkoutLog.self,
            JournalEntry.self,
            CoachMemoryEntry.self,   // Round 6: Persisted coach intelligence
            Goal.self,               // Round 13: Real coach-adjustable goals
            Habit.self               // Round 37: Coach-driven habits
        ]

    static var isUIQA: Bool {
        #if UI_TESTING
        ProcessInfo.processInfo.arguments.contains("--lumina-ui-qa")
        #else
        false
        #endif
    }

    static var preferences: UserDefaults {
        #if UI_TESTING
        if isUIQA {
            guard let raw = ProcessInfo.processInfo.environment["LUMINA_QA_ID"], let id = UUID(uuidString: raw),
                  let preferences = UserDefaults(suiteName: "Lumina-QA-" + id.uuidString) else {
                preconditionFailure("Isolated QA preferences could not be opened")
            }
            return preferences
        }
        #endif
        return .standard
    }

    @MainActor
    static let weeklyReminders = WeeklyReminderCoordinator(
        preferences: preferences, client: SystemWeeklyReminderClient())

    static func localStorageConfiguration(schema: Schema) throws -> ModelConfiguration {
        // Crash-left copies belong only to this private transfer namespace.
        // Cleanup failure must not prevent access to the original journal.
        if !JournalTransferAdmission.shared.isBusy { try? DatabaseSnapshotIO.removeAbandonedStaging() }
        #if UI_TESTING
        if isUIQA {
            guard let raw = ProcessInfo.processInfo.environment["LUMINA_QA_ID"], let id = UUID(uuidString: raw) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Lumina-QA-" + id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return ModelConfiguration(schema: schema, url: directory.appendingPathComponent("journal.sqlite"), cloudKitDatabase: .none)
        }
        #endif
        return ModelConfiguration(schema: schema, cloudKitDatabase: .none)
    }

    private let storage: Result<ModelContainer, Error> = Result {
        let schema = Schema(LuminaApp.modelTypes)
        return try ModelContainer(for: schema,
            configurations: [LuminaApp.localStorageConfiguration(schema: schema)])
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .success(let container):
                ContentView().modelContainer(container).defaultAppStorage(Self.preferences)
            case .failure:
                ContentUnavailableView(L("Could not open your records"), systemImage: "exclamationmark.triangle",
                    description: Text(L("Your existing data has not been deleted. Restart Lumina or contact support. Do not reinstall unless you have a backup.")))
                    .withAppLanguage()
            }
        }
    }
}
