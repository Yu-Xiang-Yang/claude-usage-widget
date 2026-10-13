import Foundation

enum AppLanguage {
    case zh, en
}

/// The language the user asked for; `auto` follows the first preferred system language.
enum LanguagePreference: String, CaseIterable, Identifiable {
    case auto, zh, en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动 / Auto"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

enum L10n {
    static var preference: LanguagePreference =
        LanguagePreference(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: "language") }
    }

    /// A language that is not saved; used when rendering documentation screenshots.
    static var override: AppLanguage?

    static var current: AppLanguage {
        if let override { return override }
        switch preference {
        case .zh: return .zh
        case .en: return .en
        case .auto: return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
        }
    }

    static var locale: Locale { Locale(identifier: current == .zh ? "zh_CN" : "en_US") }

    /// Monday-first row labels of the heatmap; only every other row is labelled.
    static var weekdayLabels: [String] {
        current == .zh ? ["一", "", "三", "", "五", "", "日"] : ["M", "", "W", "", "F", "", "S"]
    }

    static func month(_ number: Int) -> String {
        if current == .zh { return "\(number)月" }
        return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][(number - 1) % 12]
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    /// Month and day only, for narrow spaces.
    static func shortDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.defaultDigits).day().locale(locale))
    }

    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month().day().weekday(.abbreviated).locale(locale))
    }
}

/// Picks the Chinese or English text for the active language.
func tr(_ zh: String, _ en: String) -> String {
    L10n.current == .zh ? zh : en
}
