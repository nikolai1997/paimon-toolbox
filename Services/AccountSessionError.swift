import Foundation

enum AccountSessionError: Error, LocalizedError, Equatable {
    case networkFailure(String? = nil)
    case localStorageUnavailable(String)
    case apiFailure(String)
    case invalidResponse(String)
    case missingAccount
    case missingRole
    case requiresVerification(SignInResultPayload)
    case qrLoginPending(QrLoginPollingState)
    case stepFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .networkFailure(let detail):
            if let detail, !detail.isEmpty {
                return "网络请求失败：\(detail)"
            }
            return "网络请求失败"
        case .localStorageUnavailable(let message):
            return "本地账号存储不可用：\(message)"
        case .apiFailure(let message):
            return "接口返回错误：\(message)"
        case .invalidResponse(let message):
            return "响应内容无效：\(message)"
        case .missingAccount:
            return "请先登录米哈游账号"
        case .missingRole:
            return "没有找到已绑定的原神角色"
        case .requiresVerification(let payload):
            let hasEmbeddedChallenge = payload.gt != nil && payload.challenge != nil
            if let riskCode = payload.riskCode {
                if !hasEmbeddedChallenge {
                    return "签到触发风控验证（\(riskCode)），本次没有返回可内嵌验证参数，请到米游社完成验证后重试"
                }
                return "签到触发风控验证（\(riskCode)），请完成安全验证后重试"
            }
            if payload.isRisk == true || payload.success == 1 {
                if !hasEmbeddedChallenge {
                    return "签到触发风控验证，本次没有返回可内嵌验证参数，请到米游社完成验证后重试"
                }
                return "签到触发风控验证，请完成安全验证后重试"
            }
            return "签到需要安全验证后才能继续"
        case .qrLoginPending(let state):
            switch state {
            case .idle, .waiting:
                return "扫码登录尚未确认"
            case .scanned:
                return "已扫码，等待在手机上确认登录"
            case .confirmed:
                return "扫码登录已确认"
            case .expired:
                return "二维码已过期，请刷新后重试"
            case .canceled:
                return "登录已取消，请重新发起扫码"
            case .failed(let status):
                return "扫码登录状态异常：\(status)"
            }
        case .stepFailed(let step, let message):
            return "\(step)失败：\(message)"
        }
    }
}

extension QrLoginPollingState {
    var localizedDescription: String {
        switch self {
        case .idle:
            return "尚未生成二维码"
        case .waiting:
            return "扫码登录尚未确认"
        case .scanned:
            return "已扫码，等待在手机上确认登录"
        case .confirmed:
            return "扫码登录已确认"
        case .expired:
            return "二维码已过期，请刷新后重试"
        case .canceled:
            return "登录已取消，请重新发起扫码"
        case .failed(let status):
            return "扫码登录状态异常：\(status)"
        }
    }
}
