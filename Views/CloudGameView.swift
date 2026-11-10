import SwiftUI
import WebKit

struct CloudGameView: View {
    @Bindable var browser: CloudGameBrowser
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("云·原神", systemImage: "gamecontroller")
                    .font(.title3.weight(.semibold))
                Text("切换栏目后游戏仍在运行，可能继续消耗云游戏时长。未自动登录时请在网页中登录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if browser.webView != nil || browser.isLoading {
                    Button("退出云游戏", systemImage: "rectangle.portrait.and.arrow.right") {
                        browser.close()
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
            Divider()
            ZStack {
                CloudGameWebView(browser: browser)
                if let message = browser.errorMessage {
                    ContentUnavailableView {
                        Label("云·原神暂时无法打开", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") { browser.close(); open() }
                    }
                } else if browser.isLoading {
                    ProgressView("正在加载云·原神…")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else if browser.webView == nil {
                    ContentUnavailableView {
                        Label("云游戏已退出", systemImage: "gamecontroller")
                    } actions: {
                        Button("打开云·原神", action: open)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("cloud-game-workspace")
    }
}

private struct CloudGameWebView: NSViewRepresentable {
    let browser: CloudGameBrowser

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let webView = browser.webView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
