import Foundation

/// Synthetic data for documentation screenshots; never mixed with real usage.
enum DemoData {
    static func snapshot(now: Date = Date()) -> Snapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // A deterministic pseudo-random activity pattern: busy weekdays, quiet weekends, a few idle days.
        var seed: UInt64 = 20_260_101
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_221 &+ 1_442_695_040_888_963_407
            return Double((seed >> 33) & 0xFFFF) / 65_535
        }
        var history: [Date: DayStat] = [:]
        for back in 0..<140 {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let weekday = cal.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7
            let roll = next()
            if roll < (weekend ? 0.55 : 0.12) { continue }
            let scale = (weekend ? 0.3 : 1.0) * (0.15 + next() * 1.1)
            let tokens = Int(scale * 380_000_000)
            history[day] = DayStat(tokens: tokens, messages: tokens / 330_000,
                                   cost: Double(tokens) * 5.2e-7, output: tokens / 260)
        }
        history[today] = DayStat(tokens: 214_000_000, messages: 640, cost: 112.4, output: 820_000)

        func totals(days: Int) -> Totals {
            var t = Totals()
            for back in 0..<days {
                guard let s = history[cal.date(byAdding: .day, value: -back, to: today)!] else { continue }
                t.tokens += s.tokens; t.messages += s.messages; t.cost += s.cost; t.output += s.output
            }
            t.input = t.tokens / 90_000
            t.cacheWrite = t.tokens / 22
            t.cacheRead = t.tokens - t.output - t.input - t.cacheWrite
            return t
        }

        let quota = QuotaInfo(
            fiveHour: QuotaWindow(usedPercent: 37, resetsAt: now.addingTimeInterval(2 * 3600 + 41 * 60)),
            sevenDay: QuotaWindow(usedPercent: 52, resetsAt: now.addingTimeInterval(3 * 86_400 + 6 * 3600)),
            extras: [ExtraWindow(label: "Fable",
                                 window: QuotaWindow(usedPercent: 12, resetsAt: now.addingTimeInterval(3 * 86_400 + 6 * 3600)))],
            capturedAt: now)

        var fiveHour = Totals(); fiveHour.tokens = 48_300_000; fiveHour.cost = 21.6; fiveHour.messages = 150
        var week = Totals(); week.tokens = 612_000_000; week.cost = 301.9; week.messages = 1_850
        var fable = Totals(); fable.tokens = 41_700_000; fable.cost = 38.2; fable.messages = 120

        let days = (0..<7).map { i -> DayBar in
            let d = cal.date(byAdding: .day, value: i - 6, to: today)!
            var t = Totals()
            if let s = history[d] { t.tokens = s.tokens; t.messages = s.messages; t.cost = s.cost }
            return DayBar(date: d, totals: t)
        }

        return Snapshot(
            today: totals(days: 1), last7: totals(days: 7), last30: totals(days: 30), days: days,
            block: nil, blockIsActive: false, maxBlockTokens: 0,
            todayModels: [
                ModelShare(name: "Opus 5.5", cost: 80, share: 0.71),
                ModelShare(name: "Sonnet 5.5", cost: 24, share: 0.21),
                ModelShare(name: "Other", cost: 8, share: 0.08, isOther: true),
            ],
            quota: quota, fiveHourWindow: fiveHour, weekWindow: week, extraWindows: ["Fable": fable], history: history, updatedAt: now)
    }
}
