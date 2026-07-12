import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeLoginSheet: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss

    @State private var manualQueryTask: Task<Void, Never>?
    @State private var pollingTask: Task<Void, Never>?
    @State private var didFinishWithConfirmation = false

    private let context = CIContext()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("米游社扫码登录")
                    .font(.title2.bold())
                Text("请使用米游社 App 扫码，并在手机上确认授权。")
                    .foregroundStyle(.secondary)
            }

            Group {
                if let image = qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                } else {
                    ContentUnavailableView(
                        "等待二维码",
                        systemImage: "qrcode",
                        description: Text("点“刷新二维码”后会重新生成登录二维码。")
                    )
                    .frame(width: 280, height: 220)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(statusText)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    startManualQuery()
                } label: {
                    Label("我已确认登录", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirmLogin)

                Button {
                    cancelTasks()
                    Task { await store.startQrLogin() }
                } label: {
                    Label("刷新二维码", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isAccountBusy)

                Button("取消") {
                    cancelAndDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            restartPolling()
        }
        .onChange(of: store.qrLoginSession?.ticket) { _, _ in
            restartPolling()
        }
        .onDisappear {
            cancelTasks()
            if !didFinishWithConfirmation {
                store.cancelQrLogin(sessionID: store.qrLoginSessionID)
            }
        }
    }

    private var statusText: String {
        switch store.qrLoginState {
        case .idle:
            return "尚未生成二维码。"
        case .waiting:
            return "二维码已就绪，请扫码并在手机上确认。"
        case .scanned:
            return "已扫码，等待你在手机上完成确认。"
        case .confirmed:
            return "登录已确认，正在同步账号数据。"
        case .expired:
            return "二维码已过期，请刷新后重试。"
        case .canceled:
            return "登录已取消。"
        case .failed(let message):
            return "二维码状态异常：\(message)"
        }
    }

    private var canConfirmLogin: Bool {
        guard store.qrLoginSession != nil, !store.isAccountBusy else {
            return false
        }

        switch store.qrLoginState {
        case .waiting, .scanned:
            return true
        case .idle, .confirmed, .expired, .canceled, .failed:
            return false
        }
    }

    private var qrImage: NSImage? {
        guard let string = store.qrLoginSession?.qrURL.absoluteString else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            return nil
        }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 220, height: 220))
    }

    private func startManualQuery() {
        guard let ticket = store.qrLoginSession?.ticket,
              let sessionID = store.qrLoginSessionID else { return }
        manualQueryTask?.cancel()
        manualQueryTask = Task {
            await store.queryQrLogin(ticket: ticket, sessionID: sessionID)
            guard !Task.isCancelled,
                  store.confirmedQrLoginSessionID == sessionID else { return }
            didFinishWithConfirmation = true
            pollingTask?.cancel()
            dismiss()
        }
    }

    private func restartPolling() {
        pollingTask?.cancel()
        guard let ticket = store.qrLoginSession?.ticket,
              let sessionID = store.qrLoginSessionID else { return }
        pollingTask = Task {
            await pollLoginStatus(ticket: ticket, sessionID: sessionID)
        }
    }

    private func cancelAndDismiss() {
        let sessionID = store.qrLoginSessionID
        cancelTasks()
        store.cancelQrLogin(sessionID: sessionID)
        dismiss()
    }

    private func cancelTasks() {
        manualQueryTask?.cancel()
        manualQueryTask = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollLoginStatus(ticket: String, sessionID: UUID) async {
        while !Task.isCancelled,
              store.qrLoginSessionID == sessionID,
              store.qrLoginSession?.ticket == ticket,
              !store.accountStatus.isSignedIn {
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  store.qrLoginSessionID == sessionID,
                  store.qrLoginSession?.ticket == ticket,
                  !store.isAccountBusy else {
                continue
            }

            await store.queryQrLogin(ticket: ticket, sessionID: sessionID)

            switch store.qrLoginState {
            case .waiting, .scanned:
                continue
            case .confirmed:
                didFinishWithConfirmation = true
                dismiss()
                return
            case .idle, .expired, .canceled, .failed:
                return
            }
        }
    }
}
