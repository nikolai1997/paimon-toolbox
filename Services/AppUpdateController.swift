import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdateController: NSObject, SPUUpdaterDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var isPreparing = false
    private(set) var status = ""
    private(set) var automaticallyChecks = true
    private(set) var automaticallyDownloads = true
    var showsManualDownloadPrompt = false

    @ObservationIgnored private let configuration: AppUpdateConfiguration?
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var availabilityObservation: NSKeyValueObservation?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(configuration: AppUpdateConfiguration? = .bundled) {
        self.configuration = configuration
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        // Preserve either previous opt-out when migrating to a single switch.
        if automaticallyChecks != automaticallyDownloads { setAutomaticUpdates(false) }
        availabilityObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let available = change.newValue ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canCheckForUpdates = available && !self.isPreparing
            }
        }
    }

    var manualDownloadURL: URL? { configuration?.manualDownloadURL }
    var releasesURL: URL? { configuration?.releasesURL }
    var automaticallyUpdates: Bool { automaticallyChecks && automaticallyDownloads }

    func start() {
        guard !started else { return }
        guard let configuration, configuration.hasValidSigningKey, configuration.feedURL != nil else {
            status = "软件更新暂不可用"
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            status = "请在已安装的应用中检查更新"
            return
        }
        started = true
        controller.startUpdater()
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        if !started { start() }
        guard started, !isPreparing, controller.updater.canCheckForUpdates,
              let configuration else { return }
        isPreparing = true
        canCheckForUpdates = false
        status = "正在连接更新服务…"
        showsManualDownloadPrompt = false
        preparationTask = Task { [weak self] in
            let selected = try? await AppUpdateFeedResolver().resolve(configuration: configuration)
            guard !Task.isCancelled, let self else { return }
            self.isPreparing = false
            self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            guard selected != nil else {
                self.showConnectionFailure()
                return
            }
            self.status = "正在检查新版本…"
            self.controller.checkForUpdates(nil)
        }
    }

    func setAutomaticUpdates(_ enabled: Bool) {
        automaticallyChecks = enabled
        automaticallyDownloads = enabled
        controller.updater.automaticallyChecksForUpdates = enabled
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func feedURLString(for updater: SPUUpdater) -> String? { configuration?.feedURL?.absoluteString }

    func openManualDownload() {
        guard let url = manualDownloadURL else { return }
        showsManualDownloadPrompt = false
        NSWorkspace.shared.open(url)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "发现新版本 \(item.displayVersionString)"
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = "新版本已下载"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        canCheckForUpdates = updater.canCheckForUpdates
        guard let error = error as NSError? else { return }
        if error.domain == SUSparkleErrorDomain && error.code == 1001 {
            status = "已是最新版本"
        } else if Self.isConnectionFailure(error) {
            showConnectionFailure()
        } else if !Self.isCancellation(error) {
            status = "更新未完成，请重试"
        }
    }

    private func showConnectionFailure() {
        status = manualDownloadURL == nil ? "无法连接 GitHub 更新服务" : "GitHub 更新失败，可前往夸克下载"
        showsManualDownloadPrompt = manualDownloadURL != nil
    }

    nonisolated static func isCancellation(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isCancellation(underlying) }
        return false
    }

    nonisolated static func isConnectionFailure(_ error: NSError) -> Bool {
        guard !isCancellation(error) else { return false }
        if error.domain == NSURLErrorDomain { return true }
        return error.domain == SUSparkleErrorDomain && [1002, 2001].contains(error.code)
    }
}
