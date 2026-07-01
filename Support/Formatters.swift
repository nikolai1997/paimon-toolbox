import Foundation

enum AppFormatters {
    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func percentString(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        let integerPercent = clamped >= 1 ? 100 : Int((clamped * 100).rounded(.down))
        return "\(integerPercent)%"
    }
}
