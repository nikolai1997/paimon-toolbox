import AppKit
import SwiftUI
import WebKit

struct HoYoLABLoginSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var server = HoYoLABServer.asia
    @State private var useCookieImport = false
    @State private var cookieHeader = ""
    @State private var browser = HoYoLABLoginBrowser()
    @State private var isConnecting = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("HoYoLAB 国际服登录").font(.title2.bold())
                    Text("在 HoYoLAB 官方网页登录后，选择服务器并连接账号。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.disabled(isConnecting)
            }
            Picker("服务器 / Server", selection: $server) {
                ForEach(HoYoLABServer.allCases) { server in
                    Text(server.title).tag(server)
                }
            }
            .frame(maxWidth: 420)
            .disabled(isConnecting)

            Picker("登录方式", selection: $useCookieImport) {
                Text("网页登录").tag(false)
                Text("导入 Cookie").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(isConnecting)

            if useCookieImport {
                VStack(alignment: .leading, spacing: 12) {
                    Text("在浏览器登录 hoyolab.com，打开开发者工具 → Network，复制已登录请求的 Cookie 请求头并粘贴到下方。")
                        .foregroundStyle(.secondary)
                    SecureField("ltuid_v2=…; ltoken_v2=…; ltmid_v2=…", text: $cookieHeader)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isConnecting)
                        .accessibilityIdentifier("hoyolab-cookie-input")
                    Text("实时便签和签到使用 HoYoLAB 登录 Cookie。自动同步祈愿还需要 cookie_token_v2、account_id_v2 和 account_mid_v2；缺少时可手动导入 UIGF。")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Link("打开 HoYoLAB", destination: HoYoLABAPI.loginURL)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                if !browser.popupWebViews.isEmpty {
                    Button("返回 HoYoLAB") { browser.closePopup() }
                        .disabled(isConnecting)
                }
                HoYoLABLoginWebView(webViews: [browser.webView] + browser.popupWebViews)
                    .accessibilityIdentifier("hoyolab-login-webview")
            }

            if let error = loginError ?? browser.errorMessage {
                Text(error).foregroundStyle(.orange).textSelection(.enabled)
            }

            HStack {
                Text("登录凭据加密保存到本机文件。网页会话在关闭后清除。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isConnecting { ProgressView().controlSize(.small) }
                Button(useCookieImport ? "连接账号" : "已登录，连接账号") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || store.isAccountBusy)
                .accessibilityIdentifier("hoyolab-connect")
            }
        }
        .padding(20)
        .frame(width: 840, height: 700)
        .interactiveDismissDisabled(isConnecting)
        .onDisappear { cookieHeader = ""; browser.clear() }
    }

    private func connect() {
        isConnecting = true
        loginError = nil
        Task { @MainActor in
            defer { isConnecting = false }
            let header = useCookieImport ? cookieHeader : await browser.cookieHeader()
            do {
                _ = try HoYoLABCredentials(cookieHeader: header)
            } catch {
                loginError = error.localizedDescription
                return
            }
            if await store.completeHoYoLABLogin(cookieHeader: header, server: server) {
                cookieHeader = ""
                dismiss()
            } else {
                loginError = store.errorMessage
            }
        }
    }
}

@MainActor
@Observable
final class HoYoLABLoginBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private(set) var popupWebViews: [WKWebView] = []
    var errorMessage: String?

    init(loginURL: URL = HoYoLABAPI.loginURL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: loginURL))
    }

    func cookieHeader() async -> String {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        // Read only HoYoLAB cookies; account pages and third-party login providers
        // must not supply an unrelated credential with the same name.
        let relevant = cookies.filter { cookie in
            Self.isAccountCookie(cookie)
        }.sorted { $0.domain < $1.domain }
        return relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    nonisolated static func isAccountCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return cookie.isSecure && HoYoLABCredentials.cookieNames.contains(cookie.name)
            && (domain == "hoyolab.com" || domain.hasSuffix(".hoyolab.com"))
    }

    func clear() {
        popupWebViews.forEach { $0.stopLoading() }
        popupWebViews.removeAll()
        webView.stopLoading()
        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast, completionHandler: {}
        )
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // No credentials are injected into arbitrary pages. Only secure HoYoLAB
        // cookies are read, after the user explicitly clicks Connect.
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let scheme = navigationAction.request.url?.scheme
        guard scheme == nil || scheme == "https" || scheme == "about" else { return nil }
        // Return an actual child view using WebKit's configuration. Loading the
        // request in the opener loses window.opener, which HoYoLAB's cross-login
        // callback uses to send syncLoginStatusCallback after verification.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popupWebViews.append(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let index = popupWebViews.firstIndex(where: { $0 === webView }) else { return }
        // Closing a popup also disposes of any nested authentication windows.
        for popup in popupWebViews[index...] { popup.stopLoading() }
        popupWebViews.removeSubrange(index...)
    }

    func closePopup() {
        if let popup = popupWebViews.last {
            webViewDidClose(popup)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = "网页暂时无法打开，可切换到“导入 Cookie”登录。"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { errorMessage = nil }
}

private struct HoYoLABLoginWebView: NSViewRepresentable {
    var webViews: [WKWebView]

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        for subview in container.subviews where !webViews.contains(where: { $0 === subview }) {
            subview.removeFromSuperview()
        }
        for webView in webViews {
            if webView.superview !== container {
                webView.frame = container.bounds
                webView.autoresizingMask = [.width, .height]
                container.addSubview(webView)
            }
            // Keep the opener alive in the hierarchy while the popup is shown.
            webView.isHidden = webView !== webViews.last
        }
    }
}
