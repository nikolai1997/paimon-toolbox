import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case database
    case gachaLog
    case planner
    case account
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .database: "资料库"
        case .gachaLog: "祈愿记录"
        case .planner: "养成规划"
        case .account: "账号"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .database: "books.vertical"
        case .gachaLog: "sparkles"
        case .planner: "checklist"
        case .account: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}
