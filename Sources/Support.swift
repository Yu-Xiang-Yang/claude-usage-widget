import Foundation

enum AppPaths {
    /// ~/Library/Application Support/ClaudeUsageWidget
    /// The CLAUDE_USAGE_WIDGET_DIR environment variable overrides the location (used for testing).
    static var dataDir: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_USAGE_WIDGET_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageWidget", isDirectory: true)
    }
}

// MARK: - Subscription quota

struct QuotaWindow: Codable {
    /// 0...100
    let usedPercent: Double
    let resetsAt: Date
}

/// A per-model weekly window (for example the weekly limit of a single model family).
struct ExtraWindow: Codable {
    let label: String
    let window: QuotaWindow
}

struct QuotaInfo: Codable {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let extras: [ExtraWindow]
    let capturedAt: Date
}

enum QuotaCache {
    private static var url: URL { AppPaths.dataDir.appendingPathComponent("quota.json") }

    static func load() -> QuotaInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(QuotaInfo.self, from: data)
    }

    static func save(_ info: QuotaInfo) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(info) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}

/// Parses the JSON body of claude.ai's usage endpoint.
enum QuotaParser {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    private static func date(_ text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text)
    }

    /// Reads the unified `limits` list (kinds `session`, `weekly_all`, `weekly_scoped`) and falls back to the
    /// older top-level `five_hour` / `seven_day` objects.
    static func parse(_ text: String, now: Date = Date()) -> QuotaInfo? {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["limits"] != nil || root["five_hour"] != nil || root["seven_day"] != nil else { return nil }

        var five: QuotaWindow?
        var seven: QuotaWindow?
        var extras: [ExtraWindow] = []

        for item in (root["limits"] as? [[String: Any]]) ?? [] {
            guard let kind = item["kind"] as? String,
                  let percent = (item["percent"] as? NSNumber)?.doubleValue,
                  let resetText = item["resets_at"] as? String, let reset = date(resetText) else { continue }
            let window = QuotaWindow(usedPercent: percent, resetsAt: reset)
            switch kind {
            case "session": five = window
            case "weekly_all": seven = window
            case "weekly_scoped":
                let scope = item["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let label = model?["display_name"] as? String ?? scope?["surface"] as? String ?? tr("其他", "Other")
                extras.append(ExtraWindow(label: label, window: window))
            default: break
            }
        }

        func legacy(_ value: Any?) -> QuotaWindow? {
            guard let w = value as? [String: Any],
                  let used = (w["utilization"] as? NSNumber)?.doubleValue,
                  let resetText = w["resets_at"] as? String, let reset = date(resetText) else { return nil }
            return QuotaWindow(usedPercent: used, resetsAt: reset)
        }
        five = five ?? legacy(root["five_hour"])
        seven = seven ?? legacy(root["seven_day"])
        return QuotaInfo(fiveHour: five, sevenDay: seven, extras: extras, capturedAt: now)
    }
}

// MARK: - Daily history

struct DayStat: Codable {
    var tokens: Int
    var messages: Int
    var cost: Double
    var output: Int
}

/// Keeps per-day totals on disk. Claude Code deletes session logs after about 30 days,
/// so older days survive only here.
final class HistoryStore {
    private var days: [String: DayStat] = [:]
    private let url = AppPaths.dataDir.appendingPathComponent("history.json")
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private struct File: Codable {
        var version = 1
        var days: [String: DayStat]
    }

    init() {
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) {
            days = file.days
        }
    }

    /// Merges freshly scanned days into the stored history and returns the full history.
    /// A day is replaced only by a record set that is at least as complete (token count not lower),
    /// because deleted logs can only make a rescanned day smaller.
    func merge(_ scanned: [Date: Totals]) -> [Date: DayStat] {
        var changed = false
        for (date, t) in scanned {
            let key = formatter.string(from: date)
            let stat = DayStat(tokens: t.tokens, messages: t.messages, cost: t.cost, output: t.output)
            if let old = days[key], old.tokens > stat.tokens { continue }
            if let old = days[key], old.tokens == stat.tokens, old.messages == stat.messages { continue }
            days[key] = stat
            changed = true
        }
        if changed { save() }
        var out: [Date: DayStat] = [:]
        for (key, stat) in days {
            if let d = formatter.date(from: key) { out[Calendar.current.startOfDay(for: d)] = stat }
        }
        return out
    }

    private func save() {
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(File(days: days)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Heatmap metric

enum HeatmapMetric: String, CaseIterable, Identifiable {
    case tokens
    case messages

    var id: String { rawValue }
    var title: String { self == .tokens ? "Tokens" : tr("消息数", "Messages") }

    func value(_ s: DayStat) -> Double {
        self == .tokens ? Double(s.tokens) : Double(s.messages)
    }
}

// MARK: - Widget size

/// The size classes of macOS desktop widgets, measured on macOS 26 from the system's own widget windows:
/// a window of 180 × 180 / 360 × 180 / 360 × 360 pt holds a card inset by 8 pt on every side.
/// The extra large class follows the same 180 pt grid (720 × 360 pt window); it is not measured.
enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return tr("小（164 × 164）", "Small (164 × 164)")
        case .medium: return tr("中（344 × 164）", "Medium (344 × 164)")
        case .large: return tr("大（344 × 344）", "Large (344 × 344)")
        case .extraLarge: return tr("特大（704 × 344）", "Extra Large (704 × 344)")
        }
    }

    /// Size of the visible card in points.
    var dimensions: CGSize {
        switch self {
        case .small: return CGSize(width: 164, height: 164)
        case .medium: return CGSize(width: 344, height: 164)
        case .large: return CGSize(width: 344, height: 344)
        case .extraLarge: return CGSize(width: 704, height: 344)
        }
    }

    var padding: CGFloat { self == .small ? 14 : 16 }
}

/// Geometry shared with the system widget grid.
enum WidgetGrid {
    static let cornerRadius: CGFloat = 27
    /// Distance between a card and the screen edge or the menu bar.
    static let margin: CGFloat = 16
    /// One grid cell: a small widget plus the 16 pt of space around it.
    static let pitch: CGFloat = 180
}

// MARK: - Click action

/// What a click on the widget does.
enum ClickAction: String, CaseIterable, Identifiable {
    case app, usagePage, nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return tr("打开 Claude 应用", "Open the Claude App")
        case .usagePage: return tr("打开 claude.ai 用量页", "Open the claude.ai Usage Page")
        case .nothing: return tr("无操作", "Do Nothing")
        }
    }
}
