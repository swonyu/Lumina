import SwiftUI
import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }

    /// A saved explicit choice wins. Otherwise use the first supported language
    /// from the app/device preference order, including regional language tags.
    static func resolve(saved: String?, preferredLanguages: [String]) -> AppLanguage {
        if let saved, let language = AppLanguage(rawValue: saved) { return language }
        for preference in preferredLanguages {
            let code = preference.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-").first.map(String.init)?.lowercased()
            if let code, let language = AppLanguage(rawValue: code) { return language }
        }
        return .english
    }
}

@MainActor
@Observable
final class LocalizationManager {
    // The same preference store is used by the rest of the app. UI QA never
    // writes to production language preferences or the user's other settings.
    static let shared = LocalizationManager(preferences: LuminaApp.preferences,
        preferredLanguages: Bundle.main.preferredLocalizations,
        notificationCenter: .default)

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let notificationCenter: NotificationCenter

    private(set) var currentLanguage: AppLanguage {
        didSet {
            guard currentLanguage != oldValue else { return }
            preferences.set(currentLanguage.rawValue, forKey: "appLanguage")
            preferences.set([currentLanguage.rawValue], forKey: "AppleLanguages")
            notificationCenter.post(name: .languageDidChange, object: self)
        }
    }

    init(preferences: UserDefaults, preferredLanguages: [String], notificationCenter: NotificationCenter) {
        self.preferences = preferences
        self.notificationCenter = notificationCenter
        currentLanguage = AppLanguage.resolve(saved: preferences.string(forKey: "appLanguage"),
                                              preferredLanguages: preferredLanguages)
    }

    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }

    func localized(_ key: String, _ args: CVarArg...) -> String {
        localized(key, arguments: args)
    }

    /// Forward the argument elements, rather than the array as one CVarArg.
    func localized(_ key: String, arguments args: [CVarArg]) -> String {
        let format = localized(key, in: currentLanguage)
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
    }

    /// Stable built-in ideas can be recognized in either supported language
    /// without changing the current selection or rewriting saved habit names.
    func localized(_ key: String, in language: AppLanguage) -> String {
        let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? .main
        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("LuminaLanguageDidChange")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    LocalizationManager.shared.localized(key, arguments: args)
}

private struct AppLanguageModifier: ViewModifier {
    func body(content: Content) -> some View {
        // Observation tracks this read and updates the existing hierarchy;
        // changing language never replaces its identity, drafts or data model.
        let language = LocalizationManager.shared.currentLanguage
        content
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
    }
}

extension View {
    func withAppLanguage() -> some View { modifier(AppLanguageModifier()) }
}
