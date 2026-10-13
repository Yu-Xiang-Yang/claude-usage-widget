import AppKit
import SwiftUI
import ServiceManagement

// Command-line helpers used for verification:
//   --dump               print the aggregate as JSON and exit
//   --snapshot <png>     render the widget view to a PNG and exit
//                        (--size small|medium|large|extraLarge, --lang zh|en, --appearance light|dark, --demo)
//   --parse-usage        parse a usage JSON body from stdin and print the windows
//   --show-login         open the claude.ai sign-in window at launch
//   --login-item on|off|status   register, remove or query the login item

func dumpAggregate() {
    let scanner = UsageScanner()
    let started = Date()
    scanner.refresh()
    let s = scanner.snapshot(quota: QuotaCache.load(), history: HistoryStore().merge(scanner.dailyTotals()))
    func totals(_ t: Totals) -> [String: Any] {
        ["tokens": t.tokens, "input": t.input, "output": t.output, "cache_write": t.cacheWrite,
         "cache_read": t.cacheRead, "messages": t.messages, "cost": (t.cost * 1000).rounded() / 1000]
    }
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    var out: [String: Any] = [
        "today": totals(s.today), "last7": totals(s.last7), "last30": totals(s.last30),
        "days": s.days.map { ["date": day.string(from: $0.date), "tokens": $0.totals.tokens] },
        "history_days": s.history.count,
        "quota": s.quota.map { q -> [String: Any] in
            var o: [String: Any] = ["captured_at": ISO8601DateFormatter().string(from: q.capturedAt)]
            if let f = q.fiveHour { o["five_hour"] = ["percent": f.usedPercent, "resets_at": ISO8601DateFormatter().string(from: f.resetsAt)] }
            if let w = q.sevenDay { o["seven_day"] = ["percent": w.usedPercent, "resets_at": ISO8601DateFormatter().string(from: w.resetsAt)] }
            o["extras"] = q.extras.map { ["label": $0.label, "percent": $0.window.usedPercent] }
            if let t = s.fiveHourWindow { o["five_hour_window_tokens"] = t.tokens }
            if let t = s.weekWindow { o["seven_day_window_tokens"] = t.tokens }
            return o
        } ?? NSNull(),
        "max_block_tokens": s.maxBlockTokens,
        "block_active": s.blockIsActive,
        "scan_seconds": Date().timeIntervalSince(started),
    ]
    if let b = s.block {
        out["block"] = ["start": ISO8601DateFormatter().string(from: b.start), "tokens": b.totals.tokens,
                        "messages": b.totals.messages]
    }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

@MainActor
func renderSnapshot(to path: String) {
    _ = NSApplication.shared
    func option(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
    if let lang = option("--lang") { L10n.override = lang == "zh" ? .zh : .en }

    let controller = AppController()
    if let size = option("--size").flatMap(WidgetSize.init(rawValue:)) { controller.widgetSize = size }

    let snapshot: Snapshot
    if arguments.contains("--demo") {
        snapshot = DemoData.snapshot()
    } else {
        let scanner = UsageScanner()
        scanner.refresh()
        snapshot = scanner.snapshot(quota: QuotaCache.load(), history: HistoryStore().merge(scanner.dailyTotals()))
    }
    let model = UsageModel(preloaded: snapshot)
    model.fetchesQuota = false

    let dark = option("--appearance") == "dark"
    let size = controller.widgetSize.dimensions
    let view = WidgetView(model: model, controller: controller, interactive: false)
        .frame(width: size.width, height: size.height)
        .background(dark ? Color(white: 0.16) : Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: WidgetGrid.cornerRadius, style: .continuous))
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

func parseUsageFromStdin() {
    let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard let q = QuotaParser.parse(text) else { print("not a usage payload"); return }
    func line(_ name: String, _ w: QuotaWindow?) -> String {
        w.map { "\(name): \($0.usedPercent)% resets \(ISO8601DateFormatter().string(from: $0.resetsAt))" } ?? "\(name): none"
    }
    print(line("five_hour", q.fiveHour)); print(line("seven_day", q.sevenDay))
    for e in q.extras { print(line("extra[\(e.label)]", e.window)) }
}

/// Registers or removes this app as a login item without starting the UI.
func configureLoginItem(_ action: String) {
    switch action {
    case "on": AppController.setLoginItem(true)
    case "off": AppController.setLoginItem(false)
    default: break
    }
    let status: String
    switch SMAppService.mainApp.status {
    case .enabled: status = "enabled"
    case .requiresApproval: status = "requires approval (System Settings > General > Login Items)"
    case .notRegistered: status = "not registered"
    case .notFound: status = "not found"
    @unknown default: status = "unknown"
    }
    print("login item: \(status)")
}

let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--login-item") {
    configureLoginItem(i + 1 < arguments.count ? arguments[i + 1] : "status")
} else if arguments.contains("--probe-webauthn") {
    _ = NSApplication.shared
    let probe = WebAuthnProbe()
    probe.run()
    withExtendedLifetime(probe) { RunLoop.main.run(until: Date().addingTimeInterval(15)) }
} else if arguments.contains("--parse-usage") {
    parseUsageFromStdin()
} else if arguments.contains("--dump") {
    dumpAggregate()
} else if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    MainActor.assumeIsolated { renderSnapshot(to: arguments[i + 1]) }
} else {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    if arguments.contains("--show-login") { controller.showLoginOnLaunch = true }
    app.run()
}
