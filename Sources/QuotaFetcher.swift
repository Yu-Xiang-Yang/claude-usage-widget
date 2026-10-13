import AppKit
import WebKit

enum QuotaStatus: Equatable {
    case unknown
    case ok
    case loggedOut
    case failed(String)
}

enum QuotaFetchError: Error {
    case loggedOut
    case failed(String)
}

private let webAppName = "Version/17.4 Safari/605.1.15"

/// Passkeys need a browser entitlement that a locally built app cannot hold, so a sign-in page that offers one
/// stalls. Hiding the WebAuthn API makes Google and claude.ai fall back to password, code or device prompts.
private let hideWebAuthnScript = """
(function () {
  try { Object.defineProperty(window, 'PublicKeyCredential', { value: undefined, configurable: true, writable: true }); } catch (e) {}
  try {
    if (navigator.credentials) {
      var reject = function () { return Promise.reject(new DOMException('Not supported', 'NotSupportedError')); };
      navigator.credentials.get = reject;
      navigator.credentials.create = reject;
    }
  } catch (e) {}
})();
"""

func makeSignInConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.applicationNameForUserAgent = webAppName
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    config.userContentController.addUserScript(
        WKUserScript(source: hideWebAuthnScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    return config
}

/// Reads the plan usage that claude.ai itself displays, using the sign-in stored in this app's own WebKit data store.
/// The endpoint is not a documented API and may change without notice.
final class QuotaFetcher: NSObject, WKNavigationDelegate {
    private static let origin = "https://claude.ai"
    private static let orgDefaultsKey = "claudeOrganizationUUID"

    private let webView: WKWebView
    private var busy = false
    private var pending: ((Int?, String?, Error?) -> Void)?
    private var statusCode: Int?
    private var timeout: DispatchWorkItem?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = webAppName
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    /// Completion is always called on the main thread.
    func fetch(completion: @escaping (Result<QuotaInfo, QuotaFetchError>) -> Void) {
        guard !busy else { return }
        busy = true
        let finish: (Result<QuotaInfo, QuotaFetchError>) -> Void = { [weak self] result in
            self?.busy = false
            completion(result)
        }
        organization { [weak self] org in
            guard let self else { return }
            switch org {
            case .failure(let error):
                finish(.failure(error))
            case .success(let uuid):
                self.load("/api/organizations/\(uuid)/usage") { code, body, error in
                    if let error { return finish(.failure(.failed(error.localizedDescription))) }
                    if code == 401 { return finish(.failure(.loggedOut)) }
                    if code == 403 || code == 404 {
                        UserDefaults.standard.removeObject(forKey: Self.orgDefaultsKey)
                        return finish(.failure(.failed("HTTP \(code ?? 0)")))
                    }
                    if let info = QuotaParser.parse(body ?? "") { return finish(.success(info)) }
                    finish(.failure(.failed(tr("响应格式无法识别", "Unrecognized response"))))
                }
            }
        }
    }

    /// Resolves (and caches) the organization that owns the subscription.
    private func organization(_ completion: @escaping (Result<String, QuotaFetchError>) -> Void) {
        if let cached = UserDefaults.standard.string(forKey: Self.orgDefaultsKey) {
            return completion(.success(cached))
        }
        load("/api/organizations") { code, body, error in
            if let error { return completion(.failure(.failed(error.localizedDescription))) }
            if code == 401 { return completion(.failure(.loggedOut)) }
            guard code == 200, let data = body?.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !list.isEmpty else {
                // A challenge page or an error body: treat as signed out so the user can sign in again.
                return completion(.failure(code == 403 ? .loggedOut : .failed(tr("无法获取组织信息（HTTP \(code ?? 0)）", "Could not read the organization (HTTP \(code ?? 0))"))))
            }
            let chat = list.first { ($0["capabilities"] as? [String])?.contains("chat") == true } ?? list[0]
            guard let uuid = chat["uuid"] as? String else { return completion(.failure(.failed(tr("组织信息缺少 uuid", "Organization has no uuid")))) }
            UserDefaults.standard.set(uuid, forKey: Self.orgDefaultsKey)
            completion(.success(uuid))
        }
    }

    static func forgetOrganization() {
        UserDefaults.standard.removeObject(forKey: orgDefaultsKey)
    }

    // MARK: Navigation helpers

    private func load(_ path: String, completion: @escaping (Int?, String?, Error?) -> Void) {
        pending = completion
        statusCode = nil
        let timer = DispatchWorkItem { [weak self] in
            self?.complete(nil, nil, NSError(domain: "QuotaFetcher", code: -1,
                                              userInfo: [NSLocalizedDescriptionKey: tr("请求超时", "Request timed out")]))
        }
        timeout = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timer)
        webView.load(URLRequest(url: URL(string: Self.origin + path)!,
                                cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    private func complete(_ code: Int?, _ body: String?, _ error: Error?) {
        timeout?.cancel()
        timeout = nil
        guard let handler = pending else { return }
        pending = nil
        handler(code, body, error)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, error in
            guard let self else { return }
            self.complete(self.statusCode, result as? String, error)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(nil, nil, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        complete(nil, nil, error)
    }
}

// MARK: - Login window

/// A plain browser window on claude.ai/login that shares the fetcher's data store.
/// Pop-up windows are supported because the Google and Apple sign-in flows run in one.
final class LoginWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    /// Called whenever the page moves away from the login screen on claude.ai.
    var onPossibleLogin: (() -> Void)?
    private var window: NSWindow?
    private var popups: [NSWindow] = []

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let web = WKWebView(frame: .zero, configuration: makeSignInConfiguration())
        web.navigationDelegate = self
        web.uiDelegate = self

        let window = makeWindow(title: tr("登录 claude.ai", "Sign In to claude.ai"), size: NSSize(width: 520, height: 740), content: web)
        self.window = window
        web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        popups.forEach { $0.close() }
        window?.close()
    }

    private func makeWindow(title: String, size: NSSize, content: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = content
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        return window
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // The pop-up must use the configuration it is given, otherwise window.opener is lost.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let window = makeWindow(title: tr("登录", "Sign In"), size: NSSize(width: 480, height: 660), content: popup)
        popups.append(window)
        window.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.first { $0.contentView === webView }?.close()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host == "claude.ai",
              !url.path.hasPrefix("/login"), !url.path.hasPrefix("/logout") else { return }
        onPossibleLogin?()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window { window = nil }
        popups.removeAll { $0 === closing }
    }
}

/// Removes the stored claude.ai sign-in and everything cached for it.
func clearClaudeSession(completion: @escaping () -> Void) {
    let store = WKWebsiteDataStore.default()
    store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
        QuotaFetcher.forgetOrganization()
        QuotaCache.clear()
        completion()
    }
}

/// Debug helper: prints typeof PublicKeyCredential with and without the sign-in configuration, then exits.
final class WebAuthnProbe: NSObject, WKNavigationDelegate {
    private var views: [WKWebView] = []
    private var results: [String] = []

    func run() {
        let plain = WKWebViewConfiguration()
        plain.applicationNameForUserAgent = webAppName
        probe("default configuration", plain)
        probe("sign-in configuration", makeSignInConfiguration())
    }

    private func probe(_ name: String, _ config: WKWebViewConfiguration) {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), configuration: config)
        web.navigationDelegate = self
        views.append(web)
        web.loadHTMLString("<html><body>probe</body></html>", baseURL: URL(string: "https://claude.ai")!)
        web.setValue(name, forKey: "accessibilityLabel")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = "typeof window.PublicKeyCredential + ' | credentials.get ' + (navigator.credentials ? String(navigator.credentials.get).slice(0, 40).replace(/\\s+/g, ' ') : 'n/a')"
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            let name = (webView.value(forKey: "accessibilityLabel") as? String) ?? "?"
            self.results.append("\(name): \(value ?? "error")")
            if self.results.count == self.views.count {
                self.results.sorted().forEach { print($0) }
                exit(0)
            }
        }
    }
}
