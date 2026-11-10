import Foundation

enum PresentationPrivacy {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--hide-private-info")
    }

    static func identifier(_ value: String) -> String {
        isEnabled ? "*********" : value
    }

    static func nickname(_ value: String) -> String {
        isEnabled ? "旅行者" : value
    }
}
