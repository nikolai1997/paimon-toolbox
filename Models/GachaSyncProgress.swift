import Foundation

typealias GachaSyncProgressHandler = @MainActor @Sendable (GachaSyncProgress) -> Void

struct GachaSyncProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case authorizing
        case reading
        case waitingToRetry(seconds: Int)
        case saving
        case cancelling
    }

    var phase: Phase = .authorizing
    var bannerName: String = ""
    var bannerIndex = 0
    var bannerCount = 0
    var page = 0
    var recordsRead = 0

    var title: String {
        switch phase {
        case .authorizing: "正在连接账号…"
        case .reading: "正在读取祈愿记录…"
        case .waitingToRetry(let seconds): "服务器繁忙，等待 \(seconds) 秒后自动重试…"
        case .saving: "正在合并并保存记录…"
        case .cancelling: "正在取消更新…"
        }
    }

    var detail: String {
        guard bannerIndex > 0 else { return "历史记录较多时需要一些时间，可以继续浏览或取消。" }
        return "\(bannerName) · 卡池 \(bannerIndex)/\(bannerCount) · 第 \(page) 页"
    }

    var canCancel: Bool { phase != .saving && phase != .cancelling }
}
