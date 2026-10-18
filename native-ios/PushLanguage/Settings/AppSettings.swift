import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    var id: String { rawValue }
    var title: String { self == .english ? "English" : "Tiếng Việt" }
}

enum AppLocalization {
    private static let lock = NSLock()
    private static var selected: AppLanguage = .english

    static var language: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return selected
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            selected = newValue
        }
    }

    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let code = (language ?? self.language).rawValue
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: "appLanguage") {
            if let raw = stored as? String, let language = AppLanguage(rawValue: raw) {
                self.language = language
            } else {
                language = .english
                errorMessage = "The saved language preference is invalid. Choose a language to repair it."
            }
        } else {
            language = .english
        }
        AppLocalization.language = language
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        AppLocalization.language = value
        defaults.set(value.rawValue, forKey: "appLanguage")
        errorMessage = nil
    }
}
