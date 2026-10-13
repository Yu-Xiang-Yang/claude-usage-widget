import SwiftUI
import AppKit

extension Color {
    static let claudeAccent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let quotaWarn = Color(red: 0.91, green: 0.66, blue: 0.22)
    static let quotaCritical = Color(red: 0.84, green: 0.29, blue: 0.29)
}

private let modelPalette: [Color] = [
    .claudeAccent,
    Color(red: 0.38, green: 0.52, blue: 0.85),
    Color(red: 0.36, green: 0.68, blue: 0.62),
    Color.gray.opacity(0.6),
]

/// Everything a layout needs, so that each size class stays a small composition of shared parts.
private struct LayoutContext {
    let snapshot: Snapshot
    let status: QuotaStatus
    let metric: HeatmapMetric
    let isRefreshing: Bool
    let onLogin: () -> Void
    let onRefresh: () -> Void
}

struct WidgetView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var controller: AppController
    /// Disabled for offscreen rendering, where AppKit-backed views are unsupported.
    var interactive = true

    var body: some View {
        let size = controller.widgetSize
        Group {
            if let snapshot = model.snapshot {
                content(size, LayoutContext(
                    snapshot: snapshot, status: model.quotaStatus, metric: controller.heatmapMetric,
                    isRefreshing: model.isRefreshing, onLogin: controller.showLogin,
                    onRefresh: { model.refresh(force: true) }))
            } else {
                Text(tr("正在读取本机日志…", "Reading local logs…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(controller.language)
        .padding(size.padding)
        .frame(width: size.dimensions.width, height: size.dimensions.height, alignment: .topLeading)
        .background { if interactive { DragHandle(snap: controller.snapOrigin) } }
        .contextMenu {
            Button(tr("立即刷新", "Refresh Now")) { model.refresh(force: true) }
            Picker(tr("尺寸", "Size"), selection: $controller.widgetSize) {
                ForEach(WidgetSize.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker(tr("热力图指标", "Heatmap Metric"), selection: $controller.heatmapMetric) {
                ForEach(HeatmapMetric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("语言 / Language", selection: $controller.language) {
                ForEach(LanguagePreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(tr("登录 claude.ai…", "Sign In to claude.ai…")) { controller.showLogin() }
            Button(tr("清除登录状态", "Clear Sign-In")) { controller.clearLogin() }
            Divider()
            Toggle(tr("窗口置顶", "Keep on Top"), isOn: $controller.alwaysOnTop)
            Toggle(tr("登录时启动", "Launch at Login"), isOn: $controller.launchAtLogin)
            Divider()
            Button(tr("隐藏小组件", "Hide Widget")) { controller.setVisible(false) }
            Button(tr("退出", "Quit")) { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private func content(_ size: WidgetSize, _ ctx: LayoutContext) -> some View {
        switch size {
        case .small: SmallLayout(ctx: ctx)
        case .medium: MediumLayout(ctx: ctx)
        case .large: LargeLayout(ctx: ctx)
        case .extraLarge: ExtraLargeLayout(ctx: ctx)
        }
    }
}

// MARK: - Layouts

private struct SmallLayout: View {
    let ctx: LayoutContext

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Header(title: "Claude", trailing: nil, showsRefresh: false, ctx: ctx)
            QuotaCompactSection(ctx: ctx)
            Spacer(minLength: 0)
        }
    }
}

private struct MediumLayout: View {
    let ctx: LayoutContext

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Header(title: "Claude", trailing: nil, showsRefresh: false, ctx: ctx)
                QuotaCompactSection(ctx: ctx)
                Spacer(minLength: 0)
            }
            .frame(width: 128)
            VStack(alignment: .leading, spacing: 8) {
                Heatmap(history: ctx.snapshot.history, metric: ctx.metric,
                        spec: .init(width: 170, cellCap: 9, gap: 2.5, minCell: 6, minWeeks: 14, maxWeeks: 26,
                                    labelColumn: 14, title: tr("热力图 · \(ctx.metric.title)", "Heatmap · \(ctx.metric.title)"), legend: .none))
                Text("\(tr("今日", "Today")) \(formatTokens(ctx.snapshot.today.tokens)) · \(formatCost(ctx.snapshot.today.cost))")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LargeLayout: View {
    let ctx: LayoutContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(title: tr("Claude 用量", "Claude Usage"),
                   trailing: "\(tr("今日", "Today")) \(formatTokens(ctx.snapshot.today.tokens))", showsRefresh: true, ctx: ctx)
            QuotaStandardSection(ctx: ctx, dense: true)
            Divider().opacity(0.5)
            Heatmap(history: ctx.snapshot.history, metric: ctx.metric,
                    spec: .init(width: 312, cellCap: 11, gap: 3, minCell: 9, minWeeks: 20, maxWeeks: 26,
                                labelColumn: 16, title: tr("使用热力图 · 每日 \(ctx.metric.title)", "Activity · daily \(ctx.metric.title)"), legend: .inline))
            Spacer(minLength: 0)
        }
    }
}

private struct ExtraLargeLayout: View {
    let ctx: LayoutContext

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Header(title: tr("Claude 用量", "Claude Usage"), trailing: nil, showsRefresh: false, ctx: ctx)
                QuotaStandardSection(ctx: ctx, dense: true)
                Spacer(minLength: 0)
                ModelBar(shares: ctx.snapshot.todayModels)
                Footer(ctx: ctx)
            }
            .frame(width: 320)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 10) {
                Heatmap(history: ctx.snapshot.history, metric: ctx.metric,
                        spec: .init(width: 314, cellCap: 11, gap: 3, minCell: 9, minWeeks: 20, maxWeeks: 26,
                                    labelColumn: 16, title: tr("使用热力图 · 每日 \(ctx.metric.title)", "Activity · daily \(ctx.metric.title)"), legend: .below))
                Divider().opacity(0.5)
                PeriodsRow(snapshot: ctx.snapshot)
                BreakdownRow(totals: ctx.snapshot.today)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Header and footer

private struct Header: View {
    let title: String
    let trailing: String?
    let showsRefresh: Bool
    let ctx: LayoutContext

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.claudeAccent)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if showsRefresh {
                Button(action: ctx.onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .rotationEffect(.degrees(ctx.isRefreshing ? 180 : 0))
                        .animation(.easeInOut(duration: 0.4), value: ctx.isRefreshing)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("立即刷新", "Refresh now"))
            }
        }
        .frame(height: 16)
    }
}

private struct Footer: View {
    let ctx: LayoutContext

    var body: some View {
        let s = ctx.snapshot
        var quota = s.quota.map { tr("额度更新于 \(L10n.time($0.capturedAt))", "Quota updated \(L10n.time($0.capturedAt))") }
            ?? tr("额度数据未接入", "Quota not connected")
        switch ctx.status {
        case .loggedOut where s.quota != nil: quota += tr("（登录已失效）", " (sign-in expired)")
        case .failed where s.quota != nil: quota += tr("（最近一次获取失败）", " (last fetch failed)")
        default: break
        }
        return Text(tr("\(quota) · 日志更新于 \(L10n.time(s.updatedAt)) · 费用按 API 标价估算",
                       "\(quota) · Logs updated \(L10n.time(s.updatedAt)) · Cost estimated at API list prices"))
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Quota

/// Two stacked quota readouts for the small and medium classes.
private struct QuotaCompactSection: View {
    let ctx: LayoutContext

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 7) {
                if let quota = ctx.snapshot.quota {
                    QuotaCompact(title: tr("5 小时", "5-hour"), window: quota.fiveHour, now: context.date)
                    QuotaCompact(title: tr("每周", "Weekly"), window: quota.sevenDay, now: context.date)
                } else {
                    LocalCompact(ctx: ctx, now: context.date)
                }
            }
        }
    }
}

private struct QuotaCompact: View {
    let title: String
    let window: QuotaWindow?
    let now: Date

    var body: some View {
        let expired = window.map { $0.resetsAt <= now } ?? false
        let percent = expired ? 0 : (window?.usedPercent ?? 0)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(QuotaText.reset(window, now: now, short: true))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                Text("%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ProgressCapsule(value: percent / 100, tint: QuotaText.tint(percent), height: 5)
        }
    }
}

private struct LocalCompact: View {
    let ctx: LayoutContext
    let now: Date

    var body: some View {
        let block = ctx.snapshot.blockIsActive ? ctx.snapshot.block : nil
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("5 小时窗口（估算）", "5-hour window (est.)"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(block.map { formatTokens($0.totals.tokens) } ?? "—")
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
            Text(ctx.status == .unknown ? tr("正在获取额度…", "Fetching quota…") : tr("未获取到额度百分比", "Quota unavailable"))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Button(tr("登录 claude.ai", "Sign in to claude.ai"), action: ctx.onLogin)
                .buttonStyle(.link)
                .font(.system(size: 10.5, weight: .medium))
        }
    }
}

/// Two full quota readouts with local window totals, for the large and extra large classes.
private struct QuotaStandardSection: View {
    let ctx: LayoutContext
    let dense: Bool

    var body: some View {
        let s = ctx.snapshot
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: dense ? 8 : 14) {
                if let quota = s.quota {
                    QuotaRow(title: tr("5 小时额度", "5-hour limit"), window: quota.fiveHour, totals: s.fiveHourWindow,
                             now: context.date, dense: dense)
                    QuotaRow(title: tr("每周额度", "Weekly limit"), window: quota.sevenDay, totals: s.weekWindow,
                             now: context.date, dense: dense,
                             badge: dense && !quota.extras.isEmpty ? extrasText(quota) : nil)
                    if !dense && !quota.extras.isEmpty {
                        Text(tr("按模型每周：", "Per-model weekly: ") + extrasText(quota))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LocalEstimate(ctx: ctx, now: context.date)
                }
            }
        }
    }
}

private func extrasText(_ quota: QuotaInfo) -> String {
    quota.extras
        .map { "\($0.label) \(Int($0.window.usedPercent.rounded()))%" }
        .joined(separator: " · ")
}

private struct QuotaRow: View {
    let title: String
    let window: QuotaWindow?
    let totals: Totals?
    let now: Date
    let dense: Bool
    var badge: String?

    var body: some View {
        // A missing window means the server reports no active window, that is, no usage.
        let expired = window.map { $0.resetsAt <= now } ?? false
        let percent = expired ? 0 : (window?.usedPercent ?? 0)

        VStack(alignment: .leading, spacing: dense ? 4 : 7) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let badge {
                    Text(tr("· 按模型 ", "· ") + badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(QuotaText.reset(window, now: now, short: false))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: dense ? 24 : 30, weight: .semibold, design: .rounded).monospacedDigit())
                Text("%")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if let totals {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(formatTokens(totals.tokens)) tokens")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        Text(tr("\(formatCost(totals.cost)) · 本机该窗口", "\(formatCost(totals.cost)) · this Mac"))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            ProgressCapsule(value: percent / 100, tint: QuotaText.tint(percent), height: 6)
        }
    }
}

/// Shown until the first quota response has arrived.
private struct LocalEstimate: View {
    let ctx: LayoutContext
    let now: Date

    var body: some View {
        let snapshot = ctx.snapshot
        let block = snapshot.blockIsActive ? snapshot.block : nil
        let tokens = block?.totals.tokens ?? 0
        let fraction = Double(tokens) / Double(max(snapshot.maxBlockTokens, 1))

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(tr("5 小时窗口（本地估算）", "5-hour window (local estimate)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remaining(block))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(block == nil ? "—" : formatTokens(tokens))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                Text("tokens")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(block.map { formatCost($0.totals.cost) } ?? "")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            ProgressCapsule(value: fraction, tint: .claudeAccent, height: 6)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(tr("登录 claude.ai", "Sign in to claude.ai"), action: ctx.onLogin)
                    .buttonStyle(.link)
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
    }

    private var hint: String {
        switch ctx.status {
        case .failed(let message): return tr("额度获取失败：\(message)。当前为本地估算。", "Quota fetch failed: \(message). Showing a local estimate.")
        case .unknown: return tr("正在获取额度…", "Fetching quota…")
        default: return tr("登录 claude.ai 后显示 5 小时与每周额度。", "Sign in to claude.ai to see the 5-hour and weekly limits.")
        }
    }

    private func remaining(_ block: BlockInfo?) -> String {
        guard let block else { return tr("无活跃窗口", "No active window") }
        let seconds = max(0, Int(block.end.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? tr("剩余 \(h) 小时 \(m) 分", "\(h) h \(m) m left") : tr("剩余 \(m) 分", "\(m) m left")
    }
}

private enum QuotaText {
    static func reset(_ window: QuotaWindow?, now: Date, short: Bool) -> String {
        guard let window else { return tr("无活跃窗口", "No active window") }
        if window.resetsAt <= now { return tr("已重置", "Reset") }
        let seconds = max(0, Int(window.resetsAt.timeIntervalSince(now)))
        let d = seconds / 86_400, h = (seconds % 86_400) / 3600, m = (seconds % 3600) / 60
        let body: String
        if L10n.current == .zh {
            body = d > 0 ? "\(d) 天 \(h) 小时" : h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分"
        } else {
            body = d > 0 ? "\(d) d \(h) h" : h > 0 ? "\(h) h \(m) m" : "\(m) m"
        }
        return short ? body : tr("\(body)后重置", "Resets in \(body)")
    }

    static func tint(_ percent: Double) -> Color {
        percent >= 90 ? .quotaCritical : percent >= 70 ? .quotaWarn : .claudeAccent
    }
}

private struct ProgressCapsule: View {
    let value: Double
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Heatmap

private struct Heatmap: View {
    struct Spec {
        /// Width available for the label column and the grid.
        let width: CGFloat
        let cellCap: CGFloat
        let gap: CGFloat
        let minCell: CGFloat
        let minWeeks: Int
        let maxWeeks: Int
        let labelColumn: CGFloat
        let title: String
        let legend: Legend
    }

    enum Legend { case none, inline, below }

    let history: [Date: DayStat]
    let metric: HeatmapMetric
    let spec: Spec

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday first
        return c
    }

    /// Spans the recorded history; never fewer than minWeeks, never more than fit at the smallest cell size.
    private var weeks: Int {
        let fit = Int((spec.width - spec.labelColumn + spec.gap) / (spec.minCell + spec.gap))
        let span: Int
        if let oldest = history.keys.min() {
            span = (Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0) / 7 + 2
        } else {
            span = spec.minWeeks
        }
        return max(1, min(fit, spec.maxWeeks, max(spec.minWeeks, span)))
    }

    private var cell: CGFloat {
        let available = spec.width - spec.labelColumn - CGFloat(weeks - 1) * spec.gap
        return min(spec.cellCap, floor(available / CGFloat(weeks)))
    }

    var body: some View {
        let cal = calendar
        let weeks = self.weeks
        let cell = self.cell
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let first = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisWeek)!
        let columnDates = (0..<weeks).map { cal.date(byAdding: .day, value: $0 * 7, to: first)! }

        let values: [Date: Double] = Dictionary(uniqueKeysWithValues: columnDates.flatMap { start in
            (0..<7).compactMap { r -> (Date, Double)? in
                let d = cal.date(byAdding: .day, value: r, to: start)!
                guard d <= today, let s = history[d] else { return nil }
                return (d, metric.value(s))
            }
        })
        let active = values.values.filter { $0 > 0 }.sorted()
        let thresholds = quartiles(active)

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(spec.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                switch spec.legend {
                case .below:
                    Text(tr("近 \(weeks) 周活跃 \(active.count) 天", "\(active.count) active days in \(weeks) wk"))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                case .inline: legend(withSpacer: false)
                case .none: EmptyView()
                }
            }
            monthLabels(columnDates, cal: cal, cell: cell)
            HStack(alignment: .top, spacing: 4) {
                weekdayLabels(cell: cell)
                HStack(spacing: spec.gap) {
                    ForEach(columnDates, id: \.self) { start in
                        VStack(spacing: spec.gap) {
                            ForEach(0..<7, id: \.self) { r in
                                let d = cal.date(byAdding: .day, value: r, to: start)!
                                cellView(d, today: today, value: values[d] ?? 0, thresholds: thresholds, cell: cell)
                            }
                        }
                    }
                }
            }
            if spec.legend == .below { legend(withSpacer: true) }
        }
    }

    private func level(_ v: Double, _ t: [Double]) -> Int {
        v <= 0 ? 0 : 1 + t.filter { v > $0 }.count
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.08)
        case 1: return Color.claudeAccent.opacity(0.28)
        case 2: return Color.claudeAccent.opacity(0.50)
        case 3: return Color.claudeAccent.opacity(0.75)
        default: return Color.claudeAccent
        }
    }

    @ViewBuilder
    private func cellView(_ date: Date, today: Date, value: Double, thresholds: [Double], cell: CGFloat) -> some View {
        if date > today {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let radius = max(2, cell * 0.2)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color(level(value, thresholds)))
                .frame(width: cell, height: cell)
                .overlay {
                    if date == today {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
                    }
                }
                .help(tooltip(date, history[date]))
        }
    }

    private func tooltip(_ date: Date, _ stat: DayStat?) -> String {
        let day = L10n.day(date)
        guard let stat, stat.tokens > 0 else { return tr("\(day)：无记录", "\(day): no activity") }
        return tr("\(day)：\(formatTokens(stat.tokens)) tokens · \(stat.messages) 条消息 · \(formatCost(stat.cost))", "\(day): \(formatTokens(stat.tokens)) tokens · \(stat.messages) messages · \(formatCost(stat.cost))")
    }

    /// Level boundaries at the 25th, 50th and 75th percentile of the active days.
    private func quartiles(_ sorted: [Double]) -> [Double] {
        guard !sorted.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
    }

    private func weekdayLabels(cell: CGFloat) -> some View {
        VStack(spacing: spec.gap) {
            ForEach(0..<7, id: \.self) { r in
                Text(L10n.weekdayLabels[r])
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: spec.labelColumn - 4, height: cell)
            }
        }
    }

    private func monthLabels(_ starts: [Date], cal: Calendar, cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 10)
            ForEach(Array(starts.enumerated()), id: \.offset) { i, start in
                let month = cal.component(.month, from: start)
                let changed = i > 0 && month != cal.component(.month, from: starts[i - 1])
                let firstColumnOK = i == 0 && starts.count > 1 && month == cal.component(.month, from: starts[1])
                if changed || firstColumnOK {
                    Text(L10n.month(month))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: spec.labelColumn + CGFloat(i) * (cell + spec.gap))
                }
            }
        }
    }

    private func legend(withSpacer: Bool) -> some View {
        HStack(spacing: 3) {
            if withSpacer { Spacer() }
            Text(tr("少", "Less")).font(.system(size: 9)).foregroundStyle(.tertiary)
            ForEach(0..<5, id: \.self) { l in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(l))
                    .frame(width: 10, height: 10)
            }
            Text(tr("多", "More")).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Periods, breakdown, model split

private struct PeriodsRow: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            cell(tr("今日", "Today"), snapshot.today)
            cell(tr("近 7 日", "7 days"), snapshot.last7)
            cell(tr("近 30 日", "30 days"), snapshot.last30)
        }
    }

    private func cell(_ title: String, _ t: Totals) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(formatTokens(t.tokens))
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            Text(formatCost(t.cost))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BreakdownRow: View {
    let totals: Totals

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tr("今日 token 构成", "Today's tokens"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                item(tr("输入", "Input"), totals.input)
                item(tr("输出", "Output"), totals.output)
                item(tr("缓存写", "Cache write"), totals.cacheWrite)
                item(tr("缓存读", "Cache read"), totals.cacheRead)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func item(_ title: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Text(formatTokens(n))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelBar: View {
    let shares: [ModelShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("今日模型占比（按估算费用）", "Today's models (by est. cost)"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            if shares.isEmpty {
                Text(tr("今日暂无记录", "No activity today"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(shares.enumerated()), id: \.element.id) { i, s in
                            Capsule()
                                .fill(modelPalette[min(i, modelPalette.count - 1)])
                                .frame(width: max(4, (geo.size.width - CGFloat(shares.count - 1) * 2) * s.share))
                        }
                    }
                }
                .frame(height: 6)
                HStack(spacing: 10) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { i, s in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(modelPalette[min(i, modelPalette.count - 1)])
                                .frame(width: 6, height: 6)
                            Text("\(s.isOther ? tr("其他", "Other") : s.name) \(Int((s.share * 100).rounded()))%")
                                .font(.system(size: 10).monospacedDigit())
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Window dragging with snapping

/// Moves the borderless window by hand so that the proposed position can be snapped while dragging.
private final class DragHandleView: NSView {
    var snap: ((NSPoint, NSSize) -> NSPoint)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let proposed = NSPoint(x: startOrigin.x + mouse.x - startMouse.x,
                               y: startOrigin.y + mouse.y - startMouse.y)
        window.setFrameOrigin(snap?(proposed, window.frame.size) ?? proposed)
    }
}

private struct DragHandle: NSViewRepresentable {
    let snap: (NSPoint, NSSize) -> NSPoint

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.snap = snap
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.snap = snap
    }
}
