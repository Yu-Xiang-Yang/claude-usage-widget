import Foundation

// MARK: - Records

struct UsageRecord {
    let timestamp: Date
    let model: String
    let input: Int
    let output: Int
    let cacheWrite5m: Int
    let cacheWrite1h: Int
    let cacheRead: Int

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    var totalTokens: Int { input + output + cacheWrite + cacheRead }
    var cost: Double { Pricing.cost(of: self) }
}

// MARK: - Pricing

/// API-equivalent list prices in USD per 1M tokens, matched by longest model-id prefix.
/// The result is an estimate; subscription plans are not billed per token.
enum Pricing {
    struct Rate {
        let input: Double
        let output: Double
        let cacheRead: Double
    }

    private static let table: [(prefix: String, rate: Rate)] = [
        ("claude-fable-5-1", Rate(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Rate(input: 10, output: 50, cacheRead: 1.00)),
        ("claude-opus-5-5", Rate(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4", Rate(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5", Rate(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", Rate(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5", Rate(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4", Rate(input: 1, output: 5, cacheRead: 0.10)),
    ].sorted { $0.prefix.count > $1.prefix.count }

    private static let fallback = Rate(input: 4, output: 20, cacheRead: 0.20)

    static func rate(for model: String) -> Rate {
        table.first { model.hasPrefix($0.prefix) }?.rate ?? fallback
    }

    /// Cache writes are billed at 1.25x (5-minute TTL) and 2x (1-hour TTL) of the input price.
    static func cost(of r: UsageRecord) -> Double {
        let p = rate(for: r.model)
        let perToken = 1.0 / 1_000_000
        return perToken * (
            Double(r.input) * p.input
            + Double(r.output) * p.output
            + Double(r.cacheWrite5m) * p.input * 1.25
            + Double(r.cacheWrite1h) * p.input * 2.0
            + Double(r.cacheRead) * p.cacheRead
        )
    }
}

func modelDisplayName(_ id: String) -> String {
    var parts = (id.hasPrefix("claude-") ? String(id.dropFirst(7)) : id)
        .split(separator: "-").map(String.init)
    if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
    guard !parts.isEmpty else { return id }
    if Int(parts[0]) != nil, let familyIdx = parts.firstIndex(where: { Int($0) == nil }) {
        let family = parts[familyIdx].capitalized
        let version = parts.filter { Int($0) != nil }.joined(separator: ".")
        return "\(family) \(version)"
    }
    let version = parts.dropFirst().joined(separator: ".")
    return version.isEmpty ? parts[0].capitalized : "\(parts[0].capitalized) \(version)"
}

// MARK: - Aggregates

struct Totals {
    var tokens = 0
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var messages = 0
    var cost = 0.0

    mutating func add(_ r: UsageRecord) {
        tokens += r.totalTokens
        input += r.input
        output += r.output
        cacheWrite += r.cacheWrite
        cacheRead += r.cacheRead
        messages += 1
        cost += r.cost
    }
}

struct DayBar: Identifiable {
    var id: Date { date }
    let date: Date
    let totals: Totals
}

struct ModelShare: Identifiable {
    var id: String { name }
    let name: String
    let cost: Double
    let share: Double
    /// The remainder after the top models; its label depends on the display language.
    var isOther = false
}

struct BlockInfo {
    let start: Date
    let end: Date
    let last: Date
    var totals: Totals
}

struct Snapshot {
    let today: Totals
    let last7: Totals
    let last30: Totals
    let days: [DayBar]
    let block: BlockInfo?
    let blockIsActive: Bool
    let maxBlockTokens: Int
    let todayModels: [ModelShare]
    let quota: QuotaInfo?
    /// Local totals inside the server-side windows (reset time minus 5 h / 7 d); nil when the window is unknown or over.
    let fiveHourWindow: Totals?
    let weekWindow: Totals?
    /// Local totals inside each per-model weekly window, keyed by the window label.
    let extraWindows: [String: Totals]
    let history: [Date: DayStat]
    let updatedAt: Date
}

// MARK: - Scanner

/// Incrementally reads Claude Code session logs. Not thread-safe: use from one serial queue.
final class UsageScanner {
    static let blockLength: TimeInterval = 5 * 3600
    private static let lookbackDays = 31

    private var offsets: [String: Int] = [:]
    private var records: [String: UsageRecord] = [:]
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    private var roots: [URL] {
        var dirs: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for p in custom.split(separator: ",") {
                dirs.append(URL(fileURLWithPath: String(p).trimmingCharacters(in: .whitespaces)).appendingPathComponent("projects"))
            }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            dirs.append(home.appendingPathComponent(".claude/projects"))
            dirs.append(home.appendingPathComponent(".config/claude/projects"))
        }
        return dirs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Reading

    func refresh(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(Self.lookbackDays) * 86_400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let mtime = v.contentModificationDate, mtime >= cutoff,
                      let size = v.fileSize else { continue }
                var offset = offsets[url.path] ?? 0
                if size < offset { offset = 0 }
                if size == offset { continue }
                offsets[url.path] = offset + ingest(url: url, from: offset)
            }
        }
    }

    /// Returns the number of bytes consumed (up to the last complete line).
    private func ingest(url: URL, from offset: Int) -> Int {
        guard let file = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? file.close() }
        do { try file.seek(toOffset: UInt64(offset)) } catch { return 0 }
        guard let data = try? file.readToEnd(), !data.isEmpty else { return 0 }

        let needle = Array("\"output_tokens\"".utf8)
        var consumed = 0
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let count = raw.count
            var pos = 0
            while pos < count {
                guard let nl = memchr(base + pos, 0x0A, count - pos) else { break }
                let end = base.distance(to: nl.assumingMemoryBound(to: UInt8.self))
                let len = end - pos
                if len > 0, memmem(base + pos, len, needle, needle.count) != nil {
                    handle(line: Data(bytes: base + pos, count: len))
                }
                pos = end + 1
                consumed = pos
            }
        }
        return consumed
    }

    private func handle(line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let tsText = obj["timestamp"] as? String,
              let ts = isoFractional.date(from: tsText) ?? isoPlain.date(from: tsText)
        else { return }

        let model = message["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return }

        func int(_ dict: [String: Any], _ key: String) -> Int { (dict[key] as? NSNumber)?.intValue ?? 0 }

        var write5m = 0
        var write1h = 0
        if let cc = usage["cache_creation"] as? [String: Any] {
            write5m = int(cc, "ephemeral_5m_input_tokens")
            write1h = int(cc, "ephemeral_1h_input_tokens")
        }
        let writeTotal = int(usage, "cache_creation_input_tokens")
        if write5m + write1h < writeTotal { write5m += writeTotal - (write5m + write1h) }

        let record = UsageRecord(
            timestamp: ts, model: model,
            input: int(usage, "input_tokens"), output: int(usage, "output_tokens"),
            cacheWrite5m: write5m, cacheWrite1h: write1h,
            cacheRead: int(usage, "cache_read_input_tokens"))

        // A streamed message is logged several times; the final entry carries the largest output count.
        let messageID = message["id"] as? String ?? ""
        let requestID = obj["requestId"] as? String ?? ""
        let key = messageID.isEmpty && requestID.isEmpty
            ? (obj["uuid"] as? String ?? UUID().uuidString)
            : "\(messageID)|\(requestID)"
        if let existing = records[key], existing.output > record.output { return }
        records[key] = record
    }

    // MARK: Aggregation

    func dailyTotals() -> [Date: Totals] {
        let cal = Calendar.current
        var out: [Date: Totals] = [:]
        for r in records.values { out[cal.startOfDay(for: r.timestamp), default: Totals()].add(r) }
        return out
    }

    /// Totals of the records inside a window; `model` restricts them to model ids that contain the given name.
    private func totals(from start: Date, to end: Date, model: String? = nil) -> Totals {
        let needle = model?.lowercased()
        var t = Totals()
        for r in records.values where r.timestamp >= start && r.timestamp <= end {
            if let needle, !r.model.lowercased().contains(needle) { continue }
            t.add(r)
        }
        return t
    }

    func snapshot(now: Date = Date(), quota: QuotaInfo? = nil, history: [Date: DayStat] = [:]) -> Snapshot {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        let start7 = cal.date(byAdding: .day, value: -6, to: startToday)!
        let start30 = cal.date(byAdding: .day, value: -29, to: startToday)!

        var today = Totals(), last7 = Totals(), last30 = Totals()
        var perDay: [Date: Totals] = [:]
        var modelCost: [String: Double] = [:]
        var live: [UsageRecord] = []

        for r in records.values where r.timestamp >= start30 {
            live.append(r)
            last30.add(r)
            if r.timestamp >= start7 {
                last7.add(r)
                perDay[cal.startOfDay(for: r.timestamp), default: Totals()].add(r)
            }
            if r.timestamp >= startToday {
                today.add(r)
                modelCost[modelDisplayName(r.model), default: 0] += r.cost
            }
        }

        let days = (0..<7).map { i -> DayBar in
            let d = cal.date(byAdding: .day, value: i, to: start7)!
            return DayBar(date: d, totals: perDay[d] ?? Totals())
        }

        live.sort { $0.timestamp < $1.timestamp }
        let blocks = Self.makeBlocks(live)
        let latest = blocks.last
        let active = latest.map { now < $0.end && now.timeIntervalSince($0.last) < Self.blockLength } ?? false

        return Snapshot(
            today: today, last7: last7, last30: last30, days: days,
            block: latest, blockIsActive: active,
            maxBlockTokens: blocks.map(\.totals.tokens).max() ?? 0,
            todayModels: Self.shares(modelCost),
            quota: quota,
            fiveHourWindow: quota?.fiveHour.flatMap { $0.resetsAt > now ? totals(from: $0.resetsAt.addingTimeInterval(-Self.blockLength), to: now) : nil },
            weekWindow: quota?.sevenDay.flatMap { $0.resetsAt > now ? totals(from: $0.resetsAt.addingTimeInterval(-7 * 86_400), to: now) : nil },
            extraWindows: Dictionary(uniqueKeysWithValues: (quota?.extras ?? []).compactMap { extra in
                extra.window.resetsAt > now
                    ? (extra.label, totals(from: extra.window.resetsAt.addingTimeInterval(-7 * 86_400), to: now, model: extra.label))
                    : nil
            }),
            history: history,
            updatedAt: now)
    }

    /// Billing windows of 5 hours; a window starts at the hour of its first message.
    private static func makeBlocks(_ sorted: [UsageRecord]) -> [BlockInfo] {
        var blocks: [BlockInfo] = []
        var current: BlockInfo?
        for r in sorted {
            if var b = current, r.timestamp < b.end, r.timestamp.timeIntervalSince(b.last) < blockLength {
                b.totals.add(r)
                current = BlockInfo(start: b.start, end: b.end, last: r.timestamp, totals: b.totals)
            } else {
                if let b = current { blocks.append(b) }
                let hour = (r.timestamp.timeIntervalSince1970 / 3600).rounded(.down) * 3600
                let start = Date(timeIntervalSince1970: hour)
                var totals = Totals()
                totals.add(r)
                current = BlockInfo(start: start, end: start.addingTimeInterval(blockLength),
                                    last: r.timestamp, totals: totals)
            }
        }
        if let b = current { blocks.append(b) }
        return blocks
    }

    private static func shares(_ cost: [String: Double]) -> [ModelShare] {
        let total = cost.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = cost.sorted { $0.value > $1.value }
        var out = sorted.prefix(3).map { ModelShare(name: $0.key, cost: $0.value, share: $0.value / total) }
        let rest = sorted.dropFirst(3).reduce(0) { $0 + $1.value }
        if rest > 0 { out.append(ModelShare(name: "Other", cost: rest, share: rest / total, isOther: true)) }
        return out
    }
}

// MARK: - Formatting

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    switch v {
    case ..<1_000: return "\(n)"
    case ..<1_000_000: return String(format: "%.1fK", v / 1e3)
    case ..<1e7: return String(format: "%.2fM", v / 1e6)
    case ..<1e9: return String(format: "%.1fM", v / 1e6)
    default: return String(format: "%.2fB", v / 1e9)
    }
}

func formatCost(_ c: Double) -> String {
    c < 1000 ? String(format: "$%.2f", c) : String(format: "$%.1fK", c / 1000)
}
