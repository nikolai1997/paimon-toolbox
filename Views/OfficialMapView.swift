import SwiftUI
import WebKit

struct OfficialMapView: View {
    @Bindable var store: AppStore
    @Bindable var browser: OfficialMapBrowser
    @Bindable var floatingWindow: MapFloatingWindowController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("大地图", systemImage: "map")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    floatingWindow.present(store: store, browser: browser)
                } label: {
                    Image(systemName: "pip.enter")
                }
                .help("浮窗显示地图")
                .accessibilityLabel("浮窗显示地图")
                .disabled(browser.webView == nil)
                if store.accountStatus.isSignedIn {
                    Text(store.accountStatus.nickname ?? "米游社账号")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Button {
                    store.selectedSection = .account
                } label: {
                    Image(systemName: store.accountStatus.isSignedIn ? "person.crop.circle" : "qrcode")
                }
                .help(store.accountStatus.isSignedIn ? "管理账号" : "扫码登录")
                .accessibilityLabel(store.accountStatus.isSignedIn ? "管理账号" : "扫码登录")

                Button {
                    Task { await openMap(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新地图")
                .accessibilityLabel("刷新地图")
                .disabled(browser.isLoading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .frame(height: 48)

            Divider()

            if floatingWindow.isPresented {
                ContentUnavailableView {
                    Label("地图已在浮窗中打开", systemImage: "pip")
                } actions: {
                    Button("显示浮窗", systemImage: "pip.enter") { floatingWindow.show() }
                    Button("返回主窗口", systemImage: "pip.exit") { floatingWindow.returnToMainWindow() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OfficialMapContent(store: store, browser: browser, floatingWindow: floatingWindow)
            }
        }
        .accessibilityIdentifier("official-map-workspace")
        .onDisappear {
            if !floatingWindow.isPresented { browser.reset() }
        }
    }

    @MainActor
    private func openMap(force: Bool = false) async {
        do {
            let session = try store.mapWebSessionContext()
            await browser.open(session: session, force: force)
        } catch {
            browser.reset()
            browser.errorMessage = "无法读取地图登录信息，请到账号页刷新登录状态后重试。"
        }
    }
}

struct OfficialMapContent: View {
    @Bindable var store: AppStore
    @Bindable var browser: OfficialMapBrowser
    @Bindable var floatingWindow: MapFloatingWindowController
    var isFloatingWindow = false

    var body: some View {
        VStack(spacing: 0) {
            if !store.accountStatus.isSignedIn {
                HStack {
                    Text("未登录")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("登录米游社") { store.selectedSection = .account }
                }
                .font(.subheadline)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                Divider()
            }

            ZStack {
                MapWebView(browser: browser, floatingWindow: floatingWindow, isFloatingWindow: isFloatingWindow)
                    .opacity(browser.errorMessage == nil ? 1 : 0)

                if let message = browser.errorMessage {
                    ContentUnavailableView {
                        Label("地图暂时无法打开", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button {
                            Task { await openMap(force: true) }
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                        }
                        Button("管理账号") { store.selectedSection = .account }
                    }
                } else if browser.isLoading {
                    ProgressView("正在加载地图…")
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: store.accountStatus) {
            guard floatingWindow.isPresented == isFloatingWindow else { return }
            await openMap()
        }
    }

    @MainActor
    private func openMap(force: Bool = false) async {
        do {
            let session = try store.mapWebSessionContext()
            await browser.open(session: session, force: force)
        } catch {
            browser.reset()
            browser.errorMessage = "无法读取地图登录信息，请到账号页刷新登录状态后重试。"
        }
    }
}

private struct MapWebView: NSViewRepresentable {
    let browser: OfficialMapBrowser
    let floatingWindow: MapFloatingWindowController
    let isFloatingWindow: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard floatingWindow.isPresented == isFloatingWindow, let webView = browser.webView else {
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

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
