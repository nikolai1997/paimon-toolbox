import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case database
    case gachaLog
    case planner
    case map
    case cloudGame
    case account
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .database: "资料库"
        case .gachaLog: "祈愿记录"
        case .planner: "养成规划"
        case .map: "大地图"
        case .cloudGame: "原神，启动"
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
        case .map: "map"
        case .cloudGame: "gamecontroller"
        case .account: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}
