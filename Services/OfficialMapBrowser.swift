import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class OfficialMapBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let contentReadyScript = "Boolean(document.querySelector('.leaflet-container .leaflet-map-pane'))"
    // The official page normally sets these when its tutorials are skipped.
    // Reapply only those preferences in each isolated session, before Vue starts.
    static let completedGuideKeys = [
        "user-guide-passed", "user-guide-area-passed", "user-guide-underground-passed",
        "entrance-guide-passed", "marker-layered-exploration-guide-passed",
        "layered-exploration-guide-passed", "elevator-guide-passed",
        "setting-guide-passed", "inventory-guide-passed"
    ]

    static var skipOnboardingScript: String {
        let keys = String(decoding: try! JSONEncoder().encode(completedGuideKeys), as: UTF8.self)
        return """
        (() => {
            if (location.origin !== 'https://act.mihoyo.com' ||
                !location.pathname.startsWith('/ys/app/interactive-map/')) return;
            try {
                for (const key of \(keys)) localStorage.setItem(key, 'true');
            } catch (_) {}
        })();
        """
    }
    private(set) var webView: WKWebView?
    private(set) var isLoading = false
    var errorMessage: String?
    @ObservationIgnored private var session: MapWebSessionContext?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var readinessTask: Task<Void, Never>?

    func invalidateSession(ifAccountChangedTo accountID: String?) {
        guard session?.accountID != accountID else { return }
        reset()
    }

    func open(session: MapWebSessionContext, force: Bool = false) async {
        if !force, self.session == session, webView != nil { return }
        reset()
        self.session = session
        let expectedGeneration = generation
        isLoading = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.skipOnboardingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true

        // Install the web login before any document or first-party API loads.
        // Never share the sign-in verification WebView or inject SToken here.
        for cookie in OfficialMapNavigationPolicy.cookies(for: session) {
            await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            guard generation == expectedGeneration, !Task.isCancelled else { return }
        }
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        webView = view
        view.load(URLRequest(url: MapWebSessionContext.mapURL, timeoutInterval: 30))
        timeoutTask = Task { [weak self, weak view] in
            do { try await Task.sleep(for: .seconds(40)) } catch { return }
            guard let self, let view, self.generation == expectedGeneration, self.isLoading else { return }
            view.stopLoading()
            self.fail("地图加载超时，请检查网络后重试。")
        }
    }

    func reset() {
        generation = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        readinessTask?.cancel()
        readinessTask = nil
        if let webView {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            webView.removeFromSuperview()
            webView.configuration.websiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast,
                completionHandler: {}
            )
        }
        webView = nil
        session = nil
        isLoading = false
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        readinessTask?.cancel()
        let expectedGeneration = generation
        readinessTask = Task { [weak self, weak webView] in
            for _ in 0..<80 {
                guard let self, let webView, self.generation == expectedGeneration, !Task.isCancelled else { return }
                let ready = try? await webView.evaluateJavaScript(Self.contentReadyScript)
                if ready as? Bool == true {
                    self.timeoutTask?.cancel()
                    self.isLoading = false
                    return
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(webView, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        fail("地图页面已停止运行，请重试。")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard webView === self.webView, let url = navigationAction.request.url else {
            return .cancel
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame, url.absoluteString == "about:blank" {
            return .allow
        } else if OfficialMapNavigationPolicy.allows(url, isMainFrame: isMainFrame) {
            return .allow
        } else {
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if OfficialMapNavigationPolicy.allows(url, isMainFrame: true) {
            webView.load(navigationAction.request)
        } else if navigationAction.navigationType == .linkActivated, url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    private func handleFailure(_ view: WKWebView, error: Error) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        fail("无法加载米游社地图，请检查网络后重试。")
    }

    private func fail(_ message: String) {
        timeoutTask?.cancel()
        readinessTask?.cancel()
        isLoading = false
        errorMessage = message
    }
}
