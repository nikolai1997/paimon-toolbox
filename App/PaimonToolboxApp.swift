import SwiftUI

@main
struct PaimonToolboxApp: App {
    @State private var store: AppStore
    @State private var appUpdater = AppUpdateController()
    @AppStorage(AppAppearanceSettings.themeKey) private var appThemeRawValue = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    init() {
        if CommandLine.arguments.contains("--self-check") {
            SelfCheck.runAndExit()
        }
        _store = State(initialValue: AppStore())
    }

    var body: some Scene {
        Window("派蒙工具箱", id: "main") {
            ContentView(store: store)
                .environment(appUpdater)
                .frame(minWidth: 1100, maxWidth: .infinity, minHeight: 720, maxHeight: .infinity)
                .preferredColorScheme(appTheme.preferredColorScheme)
                .alert("GitHub 更新暂不可用", isPresented: $appUpdater.showsManualDownloadPrompt) {
                    Button("前往夸克下载") { appUpdater.openManualDownload() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("可以通过夸克网盘下载安装包，手动安装新版本。")
                }
                .task {
                    appUpdater.start()
                    await store.load()
                    store.startDeskDirectServer()
                    store.startRemoteDataRefreshMonitor()
                    store.startDeskDailyNoteRefreshMonitor()
                    await store.startAutomaticSignInMonitor()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await store.handleAppDidBecomeActive()
                        await store.refreshRemoteDataIfNeeded()
                    }
                }
                .onOpenURL { url in
                    store.routeDeepLink(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView(store: store)
                .environment(appUpdater)
                .frame(width: 520, height: 360)
                .preferredColorScheme(appTheme.preferredColorScheme)
        }
    }
}
