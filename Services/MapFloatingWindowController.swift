import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MapFloatingWindowController: NSObject, NSWindowDelegate {
    private(set) var isPresented = false
    var isPinned = true {
        didSet { panel?.level = isPinned ? .floating : .normal }
    }
    @ObservationIgnored private(set) var panel: NSPanel?
    @ObservationIgnored private weak var store: AppStore?
    @ObservationIgnored private weak var browser: OfficialMapBrowser?

    static func makePanel() -> NSPanel {
        let panel = MapFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "大地图"
        panel.contentMinSize = NSSize(width: 380, height: 360)
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setFrameAutosaveName("OfficialMapFloatingWindow")
        return panel
    }

    func present(store: AppStore, browser: OfficialMapBrowser) {
        if isPresented {
            show()
            return
        }
        self.store = store
        self.browser = browser
        let panel = Self.makePanel()
        self.panel = panel
        panel.delegate = self
        panel.level = isPinned ? .floating : .normal
        if !panel.setFrameUsingName("OfficialMapFloatingWindow") {
            let screen = NSApp.keyWindow?.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let size = NSSize(width: min(620, visible.width), height: min(600, visible.height))
                panel.setFrame(NSRect(
                    x: visible.maxX - size.width - 16,
                    y: visible.maxY - size.height - 16,
                    width: size.width, height: size.height
                ), display: false)
            }
        }
        // Move ownership before hosting the view so the inline host cannot
        // take the same WKWebView back during SwiftUI's next update.
        isPresented = true
        panel.contentView = NSHostingView(rootView: FloatingMapView(
            store: store, browser: browser, floatingWindow: self
        ))
        panel.orderFrontRegardless()
    }

    func show() {
        panel?.orderFrontRegardless()
    }

    func returnToMainWindow() {
        store?.searchText = ""
        store?.selectedSection = .map
        panel?.close()
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedPanel = notification.object as? NSPanel, closedPanel === panel else { return }
        isPresented = false
        closedPanel.delegate = nil
        closedPanel.contentView = nil
        panel = nil
        if store?.selectedSection != .map || store?.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            browser?.reset()
        }
        store = nil
        browser = nil
    }
}

private final class MapFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FloatingMapView: View {
    @Bindable var store: AppStore
    @Bindable var browser: OfficialMapBrowser
    @Bindable var floatingWindow: MapFloatingWindowController
    @AppStorage(AppAppearanceSettings.themeKey) private var themeRawValue = AppTheme.system.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("大地图", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Toggle(isOn: $floatingWindow.isPinned) {
                    Image(systemName: floatingWindow.isPinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help(floatingWindow.isPinned ? "取消置顶" : "置顶地图")
                .accessibilityLabel("地图置顶")
                Button {
                    Task { await openMap(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(browser.isLoading)
                .help("刷新地图")
                .accessibilityLabel("刷新地图")
                Button {
                    floatingWindow.returnToMainWindow()
                } label: {
                    Image(systemName: "pip.exit")
                }
                .help("返回主窗口")
                .accessibilityLabel("返回主窗口")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .frame(height: 40)
            Divider()
            OfficialMapContent(store: store, browser: browser, floatingWindow: floatingWindow, isFloatingWindow: true)
        }
        .preferredColorScheme((AppTheme(rawValue: themeRawValue) ?? .system).preferredColorScheme)
        .accessibilityIdentifier("floating-map-workspace")
    }

    private func openMap(force: Bool) async {
        do {
            await browser.open(session: try store.mapWebSessionContext(), force: force)
        } catch {
            browser.reset()
            browser.errorMessage = "无法读取地图登录信息，请到账号页刷新登录状态后重试。"
        }
    }
}
