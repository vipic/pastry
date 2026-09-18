import Foundation

/// 类型安全的本地化字符串包装器。
/// 用法：L10n["settings.tab.general"] → 根据设置语言返回对应翻译
/// 语言切换立即生效，无需重启。
enum L10n {
    nonisolated(unsafe) private static var catalog: [String: [String: String]] = loadCatalog()

    private static func loadCatalog() -> [String: [String: String]] {
        if let catalog = loadRawCatalog(from: Bundle.main) {
            return catalog
        }

        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Pastry_Pastry.bundle"),
           let resourceBundle = Bundle(url: resourceURL) {
            if let catalog = loadRawCatalog(from: resourceBundle) {
                return catalog
            }
            let compiled = loadCompiledCatalog(from: resourceBundle)
            if !compiled.isEmpty { return compiled }
        }

        // SwiftPM development/test fallback. Access this last because Bundle.module
        // traps if the generated bundle cannot be found in a repackaged .app.
        if let catalog = loadRawCatalog(from: Bundle.module) {
            return catalog
        }
        return loadCompiledCatalog(from: Bundle.module)
    }

    private static func loadRawCatalog(from bundle: Bundle) -> [String: [String: String]]? {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]]
        else { return nil }

        var catalog: [String: [String: String]] = [:]
        for (key, value) in strings {
            var localizations: [String: String] = [:]
            if let locs = value["localizations"] as? [String: [String: Any]] {
                for (lang, locValue) in locs {
                    if let unit = locValue["stringUnit"] as? [String: Any],
                       let val = unit["value"] as? String {
                        localizations[lang] = val
                    }
                }
            }
            catalog[key] = localizations
        }
        return catalog
    }

    /// 新版 SwiftPM/Xcode 构建系统会把 String Catalog 编译为各语言的 `.strings`。
    private static func loadCompiledCatalog(from bundle: Bundle) -> [String: [String: String]] {
        var catalog: [String: [String: String]] = [:]
        for language in ["zh-Hans", "en"] {
            guard let url = bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            ),
            let data = try? Data(contentsOf: url),
            let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            else { continue }

            for (key, value) in values {
                catalog[key, default: [:]][language] = value
            }
        }
        return catalog
    }

    static subscript(_ key: String) -> String {
        let lang = currentLanguage()
        if let localizations = catalog[key] {
            if let value = localizations[lang] {
                return value
            }
            // Fallback to zh-Hans (source language)
            if let value = localizations["zh-Hans"] {
                return value
            }
        }
        return key
    }

    /// 参数化本地化字符串。占位符用 %@。
    /// 用法：L10n["toolbar.selected_count", selection.selectedIds.count]
    static subscript(_ key: String, _ args: CVarArg...) -> String {
        String(format: self[key], arguments: args)
    }

    static var currentLanguageIdentifier: String {
        currentLanguage()
    }

    private static func currentLanguage() -> String {
        if let lang = UserDefaults.standard.string(forKey: UserDefaultsKeys.language), !lang.isEmpty {
            return lang
        }
        // Fallback to system language — use autoupdating locale
        if let code = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            if code.hasPrefix("zh") { return "zh-Hans" }
        }
        return "en"
    }

    /// 测试专用：强制重新加载 catalog（用于语言切换测试）
    static func reloadCatalogForTesting() {
        catalog = loadCatalog()
    }
}
