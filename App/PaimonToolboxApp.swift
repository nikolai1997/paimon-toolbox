import SwiftUI

@main
struct PaimonToolboxApp: App {
    @State private var store: AppStore
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
                .frame(minWidth: 1100, maxWidth: .infinity, minHeight: 720, maxHeight: .infinity)
                .preferredColorScheme(appTheme.preferredColorScheme)
                .task {
                    await store.load()
                    await store.startAutomaticSignInMonitor()
                    store.startRemoteDataRefreshMonitor()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
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
                .frame(width: 520, height: 360)
                .preferredColorScheme(appTheme.preferredColorScheme)
        }
    }
}
