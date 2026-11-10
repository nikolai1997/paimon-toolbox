import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class CloudGameBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let url = URL(string: "https://ys.mihoyo.com/cloud/")!
    private(set) var webView: WKWebView?
    private(set) var isLoading = false
    var errorMessage: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var accountID: String?

    func invalidateSession(ifAccountChangedTo accountID: String?) {
        guard self.accountID != accountID else { return }
        close()
    }

    func open(session: MapWebSessionContext) async {
        guard webView == nil, !isLoading else { return }
        generation = UUID()
        let expectedGeneration = generation
        accountID = session.accountID
        isLoading = true
        errorMessage = nil
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self

        // Only the web-session cookies already permitted for the official map are shared.
        // The cloud service may require its own login even when these cookies exist.
        for cookie in OfficialMapNavigationPolicy.cookies(for: session) {
            await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            guard generation == expectedGeneration, !Task.isCancelled else { return }
        }
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        webView = view
        view.load(URLRequest(url: Self.url, timeoutInterval: 30))
    }

    func close() {
        generation = UUID()
        accountID = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.loadHTMLString("", baseURL: nil)
        webView?.removeFromSuperview()
        webView?.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast,
            completionHandler: {}
        )
        webView = nil
        isLoading = false
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(webView, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        isLoading = false
        errorMessage = "云游戏页面已停止运行，请重新打开。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard webView === self.webView, let url = action.request.url else { return .cancel }
        if action.targetFrame?.isMainFrame == false { return .allow }
        guard url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return .cancel }
        if ["mihoyo.com", "miyoushe.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return .allow
        }
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        return .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url, url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        if ["mihoyo.com", "miyoushe.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            webView.load(action.request)
        } else if action.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    private func fail(_ view: WKWebView, error: Error) {
        guard view === webView, (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        errorMessage = "无法加载云·原神，请检查网络后重试。"
    }
}
