import Foundation

enum BannerKind: String, Codable, CaseIterable, Identifiable {
    case character
    case characterEvent2
    case weapon
    case chronicled
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "角色活动祈愿"
        case .characterEvent2: "角色活动祈愿-2"
        case .weapon: "武器活动祈愿"
        case .chronicled: "集录祈愿"
        case .standard: "常驻祈愿"
        }
    }
}

struct GachaRecord: Codable, Identifiable, Equatable {
    var id: String
    var time: Date
    var banner: BannerKind
    var name: String
    var itemType: String
    var rarity: Int
}

struct GachaSummary: Equatable {
    var totalPulls: Int
    var fiveStarCount: Int
    var fourStarCount: Int
    var pitySinceLastFiveStar: Int

    static func make(from records: [GachaRecord]) -> GachaSummary {
        let sorted = records.sorted { $0.time > $1.time }
        let pity = sorted.firstIndex { $0.rarity == 5 } ?? sorted.count
        return GachaSummary(
            totalPulls: records.count,
            fiveStarCount: records.filter { $0.rarity == 5 }.count,
            fourStarCount: records.filter { $0.rarity == 4 }.count,
            pitySinceLastFiveStar: pity
        )
    }
}
