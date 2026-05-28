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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
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
            JournalEntry.self
        ])
    }
}
