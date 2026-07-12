import Foundation

enum AppVersion {
    static var current: String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "development"
        }
        return value
    }
}
