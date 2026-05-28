import SwiftUI
import Foundation

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
    
    var locale: Locale {
        Locale(identifier: rawValue)
    }
    
    var layoutDirection: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }
}

@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()
    
    private(set) var currentLanguage: AppLanguage = .english {
        didSet {
            if currentLanguage != oldValue {
                UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
                UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
                UserDefaults.standard.synchronize()
                NotificationCenter.default.post(name: .languageDidChange, object: nil)
            }
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        currentLanguage = AppLanguage(rawValue: saved) ?? .english
    }
    
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
    }
    
    /// Localized string helper
    func localized(_ key: String, _ args: CVarArg...) -> String {
        let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj")
        let bundle = path != nil ? Bundle(path: path!) : Bundle.main
        
        let format = NSLocalizedString(key, tableName: "Localizable", bundle: bundle ?? .main, value: key, comment: "")
        
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
    }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("LuminaLanguageDidChange")
}

// Convenience global function
func L(_ key: String, _ args: CVarArg...) -> String {
    LocalizationManager.shared.localized(key, args)
}

// View modifier for language + RTL
extension View {
    func withAppLanguage() -> some View {
        self
            .environment(\.locale, LocalizationManager.shared.currentLanguage.locale)
            .environment(\.layoutDirection, LocalizationManager.shared.currentLanguage.layoutDirection)
    }
}
