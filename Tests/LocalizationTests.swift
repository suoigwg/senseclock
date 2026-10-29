import Foundation

@main
struct LocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Localizations")
        L10n.resourceRootOverride = root
        let cases: [([String], AppLanguage)] = [
            (["en-US"], .english), (["zh-Hans-CN"], .simplifiedChinese),
            (["zh-CN"], .simplifiedChinese), (["zh-TW"], .traditionalChinese),
            (["zh-HK"], .traditionalChinese), (["zh-Hant-US"], .traditionalChinese),
            (["zh-Hans-HK"], .simplifiedChinese), (["fr-FR"], .english),
            (["fr-FR", "zh-Hant"], .traditionalChinese), ([], .english)
        ]
        for (preferences, expected) in cases {
            precondition(AppLanguage.resolve(.system, preferredLanguages: preferences) == expected)
            precondition(AppLanguage.resolve(.english, preferredLanguages: preferences) == .english)
        }
        var catalogs: [[String: String]] = []
        for language in [AppLanguage.english, .simplifiedChinese, .traditionalChinese] {
            let url = root.appendingPathComponent(language.rawValue + ".lproj/Localizable.strings")
            let catalog = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
            catalogs.append(catalog)
            precondition(!L10n.text("Save", language: language).isEmpty)
            let message = L10n.text("Found %ld results. Confirm the region and save.", language: language)
            precondition(String(format: message, 3).contains("3"))
            precondition(L10n.text("Missing translation", language: language) == "Missing translation")
        }
        for catalog in catalogs {
            precondition(Set(catalog.keys) == Set(catalogs[0].keys), "Every language must cover the same keys")
            for (key, value) in catalog {
                for token in ["%@", "%ld"] {
                    precondition(key.components(separatedBy: token).count == value.components(separatedBy: token).count, "Format placeholders must agree")
                }
            }
        }
        precondition(L10n.text("Save", language: .simplifiedChinese) == "保存")
        precondition(L10n.text("Save", language: .traditionalChinese) == "儲存")
        precondition(L10n.text("Save", language: .english) == "Save")
        print("Localization checks passed: system language resolution, explicit override, three complete catalogs, placeholders, fallback.")
    }
}
