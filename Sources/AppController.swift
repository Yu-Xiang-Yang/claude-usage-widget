import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// The panel never becomes the active window, so the first click must act instead of only focusing it.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
            applyLevel()
        }
    }

    @Published var heatmapMetric: HeatmapMetric {
        didSet { UserDefaults.standard.set(heatmapMetric.rawValue, forKey: "heatmapMetric") }
    }

    @Published var language: LanguagePreference {
        didSet {
            L10n.preference = language
            rebuildMenu()
            updateStatus(model.snapshot)
        }
    }

    @Published var clickAction: ClickAction {
        didSet { UserDefaults.standard.set(clickAction.rawValue, forKey: "clickAction") }
    }

    @Published var widgetSize: WidgetSize {
        didSet {
            UserDefaults.standard.set(widgetSize.rawValue, forKey: "widgetSize")
            applySize()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLoginItem else { return }
            if !Self.setLoginItem(launchAtLogin) {
                syncingLoginItem = true
                launchAtLogin = Self.loginItemEnabled
                syncingLoginItem = false
            }
        }
    }
    private var syncingLoginItem = false

    let model = UsageModel()
    var showLoginOnLaunch = false
    private var panel: NSPanel?
    private var hosting: NSHostingView<WidgetView>?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin = NSPoint.zero
    private var dragMoved = false
    private var statusItem: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private var summaryItem: NSMenuItem?
    private var subscriptions = Set<AnyCancellable>()
    private let login = LoginWindowController()

    override init() {
        alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        launchAtLogin = Self.loginItemEnabled
        heatmapMetric = HeatmapMetric(rawValue: UserDefaults.standard.string(forKey: "heatmapMetric") ?? "") ?? .tokens
        language = L10n.preference
        clickAction = ClickAction(rawValue: UserDefaults.standard.string(forKey: "clickAction") ?? "") ?? .app
        widgetSize = WidgetSize(rawValue: UserDefaults.standard.string(forKey: "widgetSize") ?? "") ?? .large
        super.init()
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildEditMenu()
        login.onPossibleLogin = { [weak self] in self?.model.fetchQuota(force: true) }
        model.$quotaStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in if status == .ok { self?.login.close() } }
            .store(in: &subscriptions)
        buildPanel()
        buildStatusItem()
        model.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.updateStatus(snapshot) }
            .store(in: &subscriptions)
        model.start()
        if showLoginOnLaunch { login.show() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app again (Finder, Spotlight, Dock) shows a hidden widget, since the menu bar item can be hidden by the system.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setVisible(true)
        return true
    }

    // MARK: Drag and click

    /// Movement below this distance, in points, is still a click and must not move or snap the window.
    private static let dragThreshold: CGFloat = 4

    /// Called for every pointer event of the gesture on the card; returns true once the card is being dragged.
    @discardableResult
    func dragChanged() -> Bool {
        guard let panel else { return false }
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = panel.frame.origin
            dragMoved = false
        }
        guard let start = dragStartMouse else { return false }
        if !dragMoved {
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragThreshold else { return false }
            dragMoved = true
        }
        let proposed = NSPoint(x: dragStartOrigin.x + mouse.x - start.x, y: dragStartOrigin.y + mouse.y - start.y)
        panel.setFrameOrigin(snapOrigin(proposed, panel.frame.size))
        return true
    }

    /// A gesture that never moved is a click.
    func dragEnded() {
        let wasClick = dragStartMouse != nil && !dragMoved
        dragStartMouse = nil
        dragMoved = false
        if wasClick { handleClick() }
    }

    // MARK: Click

    private static let claudeBundleIdentifier = "com.anthropic.claudefordesktop"
    private static let claudeWebURL = URL(string: "https://claude.ai")!
    private static let usagePageURL = URL(string: "https://claude.ai/settings/usage")!

    /// Runs the configured action; the Claude app falls back to claude.ai when it is not installed.
    func handleClick() {
        switch clickAction {
        case .nothing:
            return
        case .usagePage:
            NSWorkspace.shared.open(Self.usagePageURL)
        case .app:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleIdentifier) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(Self.claudeWebURL)
            }
        }
    }

    // MARK: Sign-in

    func showLogin() { login.show() }

    func clearLogin() {
        clearClaudeSession { [weak self] in self?.model.resetQuota() }
    }

    /// An accessory app has no menu of its own; without an Edit menu the sign-in page cannot paste.
    private func buildEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    // MARK: Panel

    private func buildPanel() {
        let size = widgetSize.dimensions
        let panel = WidgetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Native desktop widgets sit flat on the wallpaper, so the window itself casts no shadow.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let hosting = FirstMouseHostingView(rootView: WidgetView(model: model, controller: self))
        panel.contentView = Self.makeBackground(wrapping: hosting)
        self.hosting = hosting
        self.panel = panel

        applyLevel()
        if !panel.setFrameUsingName("ClaudeUsageWidget") {
            if let area = NSScreen.main?.visibleFrame {
                panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - size.width - WidgetGrid.margin,
                                                   y: area.maxY - WidgetGrid.margin))
            }
        }
        panel.setFrameAutosaveName("ClaudeUsageWidget")
        applySize()
        panel.orderFrontRegardless()
    }

    /// Liquid Glass on macOS 26, the same material as system widgets; frosted glass on earlier systems.
    private static func makeBackground(wrapping content: NSView) -> NSView {
        // NSGlassEffectView exists in the macOS 26 SDK (Swift 6.2 and later); older toolchains skip it.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = WidgetGrid.cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let blur = NSVisualEffectView()
        blur.material = .underWindowBackground
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = WidgetGrid.cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    /// Resizes to the selected size class, keeping the top-left corner fixed and settling onto the widget grid.
    private func applySize() {
        guard let panel else { return }
        let size = widgetSize.dimensions
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        // snapOrigin also keeps the widget inside the visible screen area.
        frame.origin = snapOrigin(frame.origin, size)
        panel.setFrame(frame, display: true)
    }

    // MARK: Snapping

    private static let snapThreshold: CGFloat = 14

    /// Pulls a dragged widget to the screen margins, the screen centre lines and the 180 pt cells of the system widget grid.
    func snapOrigin(_ proposed: NSPoint, _ size: NSSize) -> NSPoint {
        let center = NSPoint(x: proposed.x + size.width / 2, y: proposed.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame

        var xs: [CGFloat] = [area.midX - size.width / 2]
        var ys: [CGFloat] = [area.midY - size.height / 2]
        for k in 0..<8 {
            let step = CGFloat(k) * WidgetGrid.pitch
            xs += [area.minX + WidgetGrid.margin + step, area.maxX - WidgetGrid.margin - size.width - step]
            ys += [area.maxY - WidgetGrid.margin - size.height - step, area.minY + WidgetGrid.margin + step]
        }
        func nearest(_ value: CGFloat, _ candidates: [CGFloat]) -> CGFloat {
            guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(best - value) <= Self.snapThreshold else { return value }
            return best
        }
        var origin = NSPoint(x: nearest(proposed.x, xs), y: nearest(proposed.y, ys))
        origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
        origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        return origin
    }

    private func applyLevel() {
        panel?.level = alwaysOnTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func setVisible(_ visible: Bool) {
        if visible { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
        visibilityItem?.title = visible ? tr("隐藏小组件", "Hide Widget") : tr("显示小组件", "Show Widget")
    }

    // MARK: Menu bar item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Usage")
        item.button?.imagePosition = .imageOnly
        statusItem = item
        rebuildMenu()
    }

    /// Builds the menu again, so that a language change applies to its titles.
    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        let summary = NSMenuItem(title: tr("今日 —", "Today —"), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        let visibility = NSMenuItem(title: tr("隐藏小组件", "Hide Widget"), action: #selector(toggleVisibility), keyEquivalent: "")
        let refresh = NSMenuItem(title: tr("立即刷新", "Refresh Now"), action: #selector(refreshNow), keyEquivalent: "r")
        let top = NSMenuItem(title: tr("窗口置顶", "Keep on Top"), action: #selector(toggleTop), keyEquivalent: "")
        let autostart = NSMenuItem(title: tr("登录时启动", "Launch at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        let quit = NSMenuItem(title: tr("退出", "Quit"), action: #selector(quitApp), keyEquivalent: "q")
        let signIn = NSMenuItem(title: tr("登录 claude.ai…", "Sign In to claude.ai…"), action: #selector(menuSignIn), keyEquivalent: "")
        let signOut = NSMenuItem(title: tr("清除登录状态", "Clear Sign-In"), action: #selector(menuSignOut), keyEquivalent: "")
        [visibility, refresh, top, autostart, quit, signIn, signOut].forEach { $0.target = self }
        [summary, .separator(), visibility, refresh, .separator(), signIn, signOut, .separator(), top, autostart,
         .separator(), quit].forEach(menu.addItem)
        menu.delegate = self
        item.menu = menu
        visibilityItem = visibility
        summaryItem = summary
    }

    private func updateStatus(_ snapshot: Snapshot?) {
        guard let s = snapshot else { return }
        var summary = tr("今日 \(formatTokens(s.today.tokens)) tokens · \(formatCost(s.today.cost))",
                         "Today \(formatTokens(s.today.tokens)) tokens · \(formatCost(s.today.cost))")
        if let q = s.quota, let five = q.fiveHour, let week = q.sevenDay {
            summary += tr("\n5 小时 \(Int(five.usedPercent.rounded()))% · 每周 \(Int(week.usedPercent.rounded()))%",
                          "\n5-hour \(Int(five.usedPercent.rounded()))% · Weekly \(Int(week.usedPercent.rounded()))%")
        }
        statusItem?.button?.toolTip = summary
        summaryItem?.title = summary
    }

    @objc private func toggleVisibility() { setVisible(!(panel?.isVisible ?? false)) }
    @objc private func refreshNow() { model.refresh() }
    @objc private func toggleTop() { alwaysOnTop.toggle() }
    @objc private func toggleLogin() { launchAtLogin.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func menuSignIn() { showLogin() }
    @objc private func menuSignOut() { clearLogin() }

    // MARK: Launch at login

    /// True when the app is registered as a login item, including the state that still awaits approval in System Settings.
    static var loginItemEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    @discardableResult
    static func setLoginItem(_ enabled: Bool) -> Bool {
        removeLegacyLaunchAgent()
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    /// Earlier versions wrote a LaunchAgent; it would start a second instance next to the login item.
    private static func removeLegacyLaunchAgent() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.claude-usage-widget.plist")
        try? FileManager.default.removeItem(at: url)
    }
}

extension AppController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(toggleTop): item.state = alwaysOnTop ? .on : .off
            case #selector(toggleLogin): item.state = launchAtLogin ? .on : .off
            case #selector(toggleVisibility): item.title = (panel?.isVisible ?? false) ? tr("隐藏小组件", "Hide Widget") : tr("显示小组件", "Show Widget")
            default: break
            }
        }
    }
}
