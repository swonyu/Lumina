import Foundation
import Testing
@testable import Lumina

@MainActor
struct LocalizationIntegrityTests {
    @Test func preferredLanguageAndSavedChoiceStayInTheirOwnPreferenceStore() throws {
        let suite = "Lumina-Language-Test-" + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("synthetic-value-to-preserve", forKey: "unrelatedPreference")
        let notifications = NotificationCenter()

        let first = LocalizationManager(preferences: preferences,
            preferredLanguages: ["ar-SA", "en-US"], notificationCenter: notifications)
        #expect(first.currentLanguage == .arabic)
        #expect(first.localized("Settings") == "الإعدادات")
        #expect(preferences.object(forKey: "appLanguage") == nil)

        first.setLanguage(.english)
        #expect(first.currentLanguage == .english)
        #expect(first.localized("Settings") == "Settings")
        #expect(preferences.string(forKey: "appLanguage") == "en")
        #expect(preferences.stringArray(forKey: "AppleLanguages") == ["en"])
        let reopened = LocalizationManager(preferences: preferences,
            preferredLanguages: ["ar-SA"], notificationCenter: notifications)
        #expect(reopened.currentLanguage == .english)

        reopened.setLanguage(.arabic)
        #expect(preferences.string(forKey: "appLanguage") == "ar")
        #expect(preferences.stringArray(forKey: "AppleLanguages") == ["ar"])
        #expect(preferences.string(forKey: "unrelatedPreference") == "synthetic-value-to-preserve")
        #expect(reopened.localized("Morning sunlight exposure", in: .english) == "Morning sunlight exposure")
        #expect(reopened.localized("Morning sunlight exposure", in: .arabic) == "التعرض لضوء الشمس صباحًا")
        let arabicIdeas = LuminaViewModel.localHabitIdeas(excluding: ["morning sunlight exposure"], language: .arabic)
        #expect(arabicIdeas.count == 3)
        #expect(!arabicIdeas.contains("التعرض لضوء الشمس صباحًا"))
        let englishIdeas = LuminaViewModel.localHabitIdeas(excluding: ["التعرض لضوء الشمس صباحًا"], language: .english)
        #expect(englishIdeas.count == 3)
        #expect(!englishIdeas.contains("Morning sunlight exposure"))

        #expect(AppLanguage.resolve(saved: "en", preferredLanguages: ["ar-SA"]) == .english)
        #expect(AppLanguage.resolve(saved: "ar", preferredLanguages: ["en-US"]) == .arabic)
        #expect(AppLanguage.resolve(saved: nil, preferredLanguages: ["fr-FR", "AR_sa"]) == .arabic)
        #expect(AppLanguage.resolve(saved: "unsupported", preferredLanguages: ["fr-FR"]) == .english)
        // The real saved-workout journey crashed in UIDatePicker.setLocale
        // when numeric options leaked into the UI environment. Keep the UI
        // locale ordinary while requiring Arabic formatting for draft values.
        #expect(AppLanguage.arabic.locale.identifier == "ar")
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.arabic.numericLocale.numberingSystem.identifier == "arab")
        #expect(AppLanguage.arabic.numericLocale.decimalSeparator == "٫")
        #expect(AppLanguage.english.numericLocale.decimalSeparator == ".")
    }
}
