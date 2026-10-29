import Foundation

enum AppLanguage: String, CaseIterable {
    case system, english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"

    var title: String {
        switch self {
        case .system: return L10n.text("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }

    static func resolve(_ selection: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        guard selection == .system else { return selection }
        for identifier in preferredLanguages {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
            if parts.first == "en" { return .english }
            if parts.first == "zh" {
                return parts.contains("hant") || (!parts.contains("hans") && parts.contains(where: { ["tw", "hk", "mo"].contains($0) })) ? .traditionalChinese : .simplifiedChinese
            }
        }
        return .english
    }
}

private final class LocalizationBundleToken: NSObject {}

enum L10n {
    // Standalone test executables can use the source catalogs without a bundle.
    static var resourceRootOverride: URL?
    private static let preferences = ClockPreferences()
    private static let preferredLanguages = Locale.preferredLanguages
    private static let shippedBundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.filter { $0 != .system }.compactMap { language in
            guard let url = Bundle(for: LocalizationBundleToken.self).resourceURL?.appendingPathComponent(language.rawValue + ".lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            return (language, bundle)
        })
    static let didChange = Notification.Name("SenseClockLanguageDidChange")
    static var language: AppLanguage {
        AppLanguage.resolve(preferences.language, preferredLanguages: preferredLanguages)
    }
    static var locale: Locale { Locale(identifier: language.rawValue) }
    static var geocodingLanguage: String { language == .english ? "en" : "zh" }

    static func text(_ key: String, language selectedLanguage: AppLanguage? = nil) -> String {
        let resolved = selectedLanguage ?? language
        let bundle: Bundle?
        if let root = resourceRootOverride {
            bundle = Bundle(url: root.appendingPathComponent(resolved.rawValue + ".lproj"))
        } else {
            bundle = shippedBundles[resolved]
        }
        guard let bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
