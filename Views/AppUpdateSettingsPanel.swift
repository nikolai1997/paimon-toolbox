import SwiftUI

struct AppUpdateSettingsPanel: View {
    @Environment(AppUpdateController.self) private var updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("软件更新").font(.headline)
                Spacer()
                Text("当前版本 \(AppVersion.current)").foregroundStyle(.secondary)
            }
            Toggle("自动更新软件", isOn: Binding(
                get: { updater.automaticallyUpdates },
                set: { updater.setAutomaticUpdates($0) }
            ))
            HStack {
                Button { updater.checkForUpdates() } label: {
                    Label("检查软件更新", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!updater.canCheckForUpdates || updater.isPreparing)
                if let url = updater.manualDownloadURL {
                    Link(destination: url) {
                        Label("夸克网盘下载", systemImage: "icloud.and.arrow.down")
                    }
                }
                if let url = updater.releasesURL {
                    Link(destination: url) { Label("版本历史", systemImage: "clock.arrow.circlepath") }
                }
            }
            if !updater.status.isEmpty {
                Text(updater.status).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }
}
