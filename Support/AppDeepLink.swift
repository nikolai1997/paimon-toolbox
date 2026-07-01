import Foundation

enum AppDeepLink: Equatable {
    case accountSignIn
    case gacha
    case planner
    case overview
    case widgetRefresh

    init?(url: URL) {
        guard url.scheme == "paimontoolbox" else { return nil }
        let host = url.host(percentEncoded: false) ?? ""
        let path = url.pathComponents.filter { $0 != "/" }
        switch (host, path) {
        case ("account", ["signin"]):
            self = .accountSignIn
        case ("gacha", []):
            self = .gacha
        case ("planner", []):
            self = .planner
        case ("overview", []):
            self = .overview
        case ("widget", ["refresh"]):
            self = .widgetRefresh
        default:
            return nil
        }
    }
}
