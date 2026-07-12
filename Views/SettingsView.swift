import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: AppStore
    @AppStorage(RemoteDataSettings.offlinePackageURLKey) private var offlinePackageURL = RemoteDataSettings.defaultOfflinePackageURLString
    @AppStorage(RemoteDataSettings.autoRefreshEnabledKey) private var isAutoRefreshEnabled = true
    @AppStorage(AutoSignInSettings.enabledKey) private var isAutoSignInEnabled = false
    @AppStorage(AutoSignInSettings.windowKey) private var autoSignInWindowRawValue = AutoSignInSettings.defaultWindow.rawValue
    @AppStorage(AppAppearanceSettings.themeKey) private var appThemeRawValue = AppTheme.system.rawValue
    @State private var isImportingDataPackage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection("外观") {
                    Picker("主题", selection: $appThemeRawValue) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("跟随系统会使用 macOS 当前外观；白天和黑夜会固定 App 显示主题。")
                        .foregroundStyle(.secondary)
                }

                settingsSection("账号与签到") {
                    Toggle("启动后每天自动签到", isOn: $isAutoSignInEnabled)
                        .onChange(of: isAutoSignInEnabled) { _, _ in
                            Task {
                                await store.runAutomaticSignInCheck()
                            }
                        }
                    Picker("自动签到时间", selection: $autoSignInWindowRawValue) {
                        ForEach(AutoSignInWindow.allCases) { window in
                            Text("\(window.title) \(window.timeRangeText)").tag(window.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: autoSignInWindowRawValue) { _, _ in
                        Task {
                            await store.runAutomaticSignInCheck()
                        }
                    }
                    Text("开启后，App 打开且米游社账号已登录时，会在 \(selectedAutoSignInWindow.timeRangeText) 内随机选择一次签到；如果窗口已过且今天还没签，会在下一次检查时尝试。触发安全验证时会先刷新状态确认是否已经签上，仍未签到才保留验证提示。")
                        .foregroundStyle(.secondary)
                }

                settingsSection("桌面小组件") {
                    WidgetPreviewPanel(snapshot: store.widgetSnapshot)
                    Text("小组件读取本机快照；签到动作会打开 App 处理账号、验证码和错误提示。")
                        .foregroundStyle(.secondary)
                }

                settingsSection("静态资源") {
                    Toggle("启动时自动从 GitHub 更新", isOn: $isAutoRefreshEnabled)
                    Text("开启后，App 启动时会自动从内置数据源更新资料库；关闭后只使用本机缓存或 App 内置基础数据。")
                        .foregroundStyle(.secondary)
                    Button {
                        Task {
                            await store.refreshMetadata(from: RemoteDataSettings.githubMetadataURLString)
                        }
                    } label: {
                        Label("刷新资料库缓存", systemImage: "arrow.down.doc")
                    }
                }

                settingsSection("离线资料包") {
                    TextField("网盘 data-pack.zip 分享链接", text: $offlinePackageURL)
                    Text("GitHub 无法访问时，可从网盘下载 data-pack.zip 后在这里导入。")
                        .foregroundStyle(.secondary)
                    if let url = URL(string: offlinePackageURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                       !offlinePackageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Link(destination: url) {
                            Label("打开网盘下载链接", systemImage: "link")
                        }
                    }
                    Button {
                        isImportingDataPackage = true
                    } label: {
                        Label("导入 data-pack.zip", systemImage: "archivebox")
                    }
                }

                settingsSection("隐私声明") {
                    Text("本应用仅在本机处理账号凭据、抽卡记录和养成计划。除使用资料库自动更新、导入导出文件或使用米游社相关功能外，不会主动上传个人数据。")
                        .foregroundStyle(.secondary)
                }

                if let message = store.successMessage {
                    GlassSection {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    }
                }

                if let error = store.errorMessage {
                    GlassSection {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    }
                }
            }
            .glassPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.clear)
        .fileImporter(
            isPresented: $isImportingDataPackage,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                Task {
                    await store.importMetadataPackage(from: url)
                }
            case .failure(let error):
                store.successMessage = nil
                store.errorMessage = "选择数据包失败：\(error.localizedDescription)"
            }
        }
    }

    private var selectedAutoSignInWindow: AutoSignInWindow {
        AutoSignInWindow(rawValue: autoSignInWindowRawValue) ?? AutoSignInSettings.defaultWindow
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }
}
