import SwiftUI

struct DeskSettingsPanel: View {
    @Bindable var store: AppStore
    @State private var directBoardDisplayCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mac 直连摆件", systemImage: "laptopcomputer.and.iphone")
                    .font(.headline)
                Spacer()
                Text(store.deskDirectServerStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.deskDirectPairingRequest == nil ? Color.secondary : Color.orange)
            }

            if !store.accountStatus.isSignedIn {
                Text("登录后，工具箱会在本机启动局域网服务。摆件只接收脱敏后的原神状态和受限动作。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let request = store.deskDirectPairingRequest {
                Text("发现摆件：\(request.deviceID)")
                    .font(.subheadline)
                Text("屏幕配对码：\(request.displayCode)")
                    .font(.title3.monospaced().weight(.semibold))
                    .textSelection(.enabled)
                Text("确认后会为这台摆件生成独立访问令牌；令牌不会显示在界面或日志中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("输入摆件上的 8 位配对码", text: $directBoardDisplayCode)
                        .textFieldStyle(.roundedBorder)
                    Button("确认绑定") {
                        store.approveDeskDirectPairing(displayCode: directBoardDisplayCode)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(directBoardDisplayCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 8)
                    Button("拒绝") {
                        store.rejectDeskDirectPairing()
                        directBoardDisplayCode = ""
                    }
                    .buttonStyle(.bordered)
                }
                Text("输入与摆件屏幕一致的 8 位配对码后确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("扫描同一 Wi‑Fi 内的摆件；选择后将在摆件屏幕上确认连接。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.isScanningDeskDevices ? "正在扫描…" : "扫描摆件") {
                    Task { await store.scanDeskDevices() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isScanningDeskDevices)
                ForEach(store.discoveredDeskDevices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name).font(.subheadline.weight(.semibold))
                            Text((device.host.isEmpty ? "地址待发现" : device.host) + " · " + deskConnectionText(device.status))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.status == "available" || device.status == "paired" {
                            Button(device.status == "paired" ? "重新连接" : "连接") { Task { await store.connectDeskDevice(device) } }
                                .buttonStyle(.bordered)
                        } else if device.status == "awaiting_confirmation" {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(device.status == "connected" ? "已连接" : "已绑定", systemImage: device.status == "connected" ? "checkmark.circle.fill" : "link.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(device.status == "connected" ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 14)
        .accessibilityIdentifier("mac-direct-desk-panel")
    }

    private func deskConnectionText(_ status: String) -> String {
        switch status {
        case "connected": "已连接 · 同步正常"
        case "paired": "已授权 · 正在建立同步"
        case "saved": "已绑定 · 等待恢复在线"
        case "awaiting_confirmation": "等待摆件确认"
        default: "可连接"
        }
    }
}
