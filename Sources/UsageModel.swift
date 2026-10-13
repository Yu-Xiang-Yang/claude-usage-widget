import Foundation

/// Publishes the latest aggregate. Local logs are rescanned every refresh; the plan quota is fetched at most once a minute.
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var quotaStatus: QuotaStatus = .unknown

    /// Disabled for offscreen rendering.
    var fetchesQuota = true

    private let scanner = UsageScanner()
    private let history = HistoryStore()
    private let queue = DispatchQueue(label: "claude-usage.scan", qos: .utility)
    private lazy var fetcher = QuotaFetcher()
    private var quota: QuotaInfo? = QuotaCache.load()
    private var lastQuotaFetch = Date.distantPast
    private var fetchingQuota = false
    private var rebuilding = false
    private var rebuildQueued = false
    private var timer: Timer?

    init(preloaded: Snapshot? = nil) {
        snapshot = preloaded
    }

    func start(interval: TimeInterval = 30) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Must be called on the main thread.
    func refresh(force: Bool = false) {
        rebuild()
        fetchQuota(force: force)
    }

    func fetchQuota(force: Bool) {
        guard fetchesQuota, !fetchingQuota else { return }
        guard force || Date().timeIntervalSince(lastQuotaFetch) >= 55 else { return }
        fetchingQuota = true
        lastQuotaFetch = Date()
        fetcher.fetch { [weak self] result in
            guard let self else { return }
            self.fetchingQuota = false
            switch result {
            case .success(let info):
                self.quota = info
                QuotaCache.save(info)
                self.quotaStatus = .ok
                self.rebuild()
            case .failure(.loggedOut):
                self.quotaStatus = .loggedOut
            case .failure(.failed(let message)):
                self.quotaStatus = .failed(message)
            }
        }
    }

    /// Forgets the stored quota after the sign-in has been cleared.
    func resetQuota() {
        quota = nil
        quotaStatus = .loggedOut
        rebuild()
    }

    private func rebuild() {
        guard !rebuilding else { rebuildQueued = true; return }
        rebuilding = true
        isRefreshing = true
        let quota = self.quota
        queue.async { [weak self] in
            guard let self else { return }
            self.scanner.refresh()
            let merged = self.history.merge(self.scanner.dailyTotals())
            let result = self.scanner.snapshot(quota: quota, history: merged)
            DispatchQueue.main.async {
                self.snapshot = result
                self.rebuilding = false
                self.isRefreshing = false
                if self.rebuildQueued {
                    self.rebuildQueued = false
                    self.rebuild()
                }
            }
        }
    }
}
