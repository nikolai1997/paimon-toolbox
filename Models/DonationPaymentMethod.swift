import Foundation

enum DonationPaymentMethod: String, CaseIterable, Identifiable {
    case wechat
    case alipay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: "微信"
        case .alipay: "支付宝"
        }
    }

    var imageURL: URL? {
        Bundle.module.url(forResource: rawValue, withExtension: "png")
    }
}
