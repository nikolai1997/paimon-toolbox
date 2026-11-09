import AppKit
import SwiftUI

struct DonationSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var paymentMethod: DonationPaymentMethod = .wechat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭赞赏窗口")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Text("支持派蒙工具箱")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 6)

            Text("如果派蒙工具箱对你有帮助，欢迎请开发者喝杯咖啡。\n你的支持，是我持续维护和改进的动力。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                ForEach(DonationPaymentMethod.allCases) { method in
                    Button {
                        paymentMethod = method
                    } label: {
                        Text(method.title)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 138, height: 40)
                            .foregroundStyle(paymentMethod == method ? Color.white : Color.secondary)
                            .background(
                                paymentMethod == method ? tint(for: method) : Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(paymentMethod == method ? .isSelected : [])
                    .accessibilityIdentifier("donation-method-\(method.rawValue)")
                }
            }
            .padding(.top, 24)

            paymentCode
                .frame(width: 288, height: 288)
                .background(.white)
                .padding(.top, 24)

            Text("感谢每一份心意")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            Text("自愿赞赏，不影响任何功能的使用。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Button("下次再说") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .frame(width: 500)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var paymentCode: some View {
        if let url = paymentMethod.imageURL,
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .accessibilityLabel("\(paymentMethod.title)赞赏码")
                .accessibilityIdentifier("donation-payment-code")
        } else {
            ContentUnavailableView("赞赏码暂不可用", systemImage: "qrcode")
        }
    }

    private func tint(for method: DonationPaymentMethod) -> Color {
        switch method {
        case .wechat: Color(red: 0.06, green: 0.62, blue: 0.39)
        case .alipay: Color(red: 0.06, green: 0.45, blue: 0.95)
        }
    }
}
