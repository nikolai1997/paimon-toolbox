import SwiftUI
import WebKit

struct AnnouncementReaderView: View {
    var item: AnnouncementItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var page: AnnouncementPage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadAttempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let url = item.readableURL {
                    Button { openURL(url) } label: {
                        Image(systemName: "safari")
                    }
                    .help("在浏览器中打开")
                    .accessibilityLabel("在浏览器中打开")
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .help("关闭")
                .accessibilityLabel("关闭公告")
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.borderless)
            .padding(20)

            Divider()

            ZStack {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("公告加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button { loadAttempt += 1 } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                    }
                } else if let page {
                    PublicAnnouncementWebView(
                        page: page,
                        isLoading: $isLoading,
                        errorMessage: $errorMessage,
                        openLink: { openURL($0) }
                    )
                    .id(loadAttempt)
                }
                if isLoading && errorMessage == nil {
                    ProgressView("正在加载公告…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 640)
        .task(id: loadAttempt) { await loadPage() }
    }

    @MainActor
    private func loadPage() async {
        page = nil
        errorMessage = nil
        isLoading = true
        if let url = item.readableURL {
            page = .web(url)
            return
        }
        do {
            let html = try await AnnouncementContentService().fetchHTML(for: item)
            try Task.checkCancellation()
            page = .html(html)
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private enum AnnouncementPage {
    case html(String)
    case web(URL)
}

private struct PublicAnnouncementWebView: NSViewRepresentable {
    var page: AnnouncementPage
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    var openLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage, openLink: openLink)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if case .html = page {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        switch page {
        case .html(let html):
            view.loadHTMLString(Self.document(html), baseURL: URL(string: "https://hk4e-ann-api.mihoyo.com"))
        case .web(let url):
            view.load(URLRequest(url: url, timeoutInterval: 25))
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.stopLoading()
    }

    private static func document(_ html: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline' https:; media-src https:; base-uri 'none'; form-action 'none'">
        <style>
        /* Official mobile announcements use 0.1rem for normal body text. */
        :root { color-scheme: light dark; font-size: 160px; }
        body { margin: 0; padding: 28px; font: 16px/1.8 -apple-system, sans-serif;
               overflow-wrap: anywhere; color: #303030; background: #fff; }
        img, video { max-width: 100% !important; height: auto !important; }
        table { max-width: 100%; } a { color: #0878d1; }
        details { margin: 8px 0; }
        summary { cursor: pointer; padding: 6px 0; }
        details[open] > summary { font-weight: 600; }
        .expansion-content { padding: 4px 0 12px 20px; }
        @media (prefers-color-scheme: dark) {
            body { color: #eee; background: #202020; }
            span[style*="color"] { color: inherit !important; }
            a { color: #70baff; }
        }
        </style></head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoading: Binding<Bool>
        var errorMessage: Binding<String?>
        var openLink: (URL) -> Void

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>, openLink: @escaping (URL) -> Void) {
            self.isLoading = isLoading
            self.errorMessage = errorMessage
            self.openLink = openLink
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }
            guard url.scheme?.lowercased() == "https" else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                openLink(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private func fail(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isLoading.wrappedValue = false
            errorMessage.wrappedValue = "公告页面加载中断，请重试。"
        }
    }
}
