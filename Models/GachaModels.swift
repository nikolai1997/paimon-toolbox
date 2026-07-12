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

enum GachaPool: String, CaseIterable, Identifiable {
    case activity
    case standard
    case weapon
    case chronicled

    var id: String { rawValue }

    var kinds: Set<BannerKind> {
        switch self {
        case .activity: [.character, .characterEvent2]
        case .standard: [.standard]
        case .weapon: [.weapon]
        case .chronicled: [.chronicled]
        }
    }

    var representativeBanner: BannerKind {
        switch self {
        case .activity: .character
        case .standard: .standard
        case .weapon: .weapon
        case .chronicled: .chronicled
        }
    }

    func contains(_ banner: BannerKind) -> Bool {
        kinds.contains(banner)
    }
}

struct GachaRecord: Codable, Identifiable, Equatable {
    var uid: String? = nil
    var itemID: String? = nil
    var id: String
    var time: Date
    var banner: BannerKind
    var name: String
    var itemType: String
    var rarity: Int

    static func sortedNewestFirst(_ records: [GachaRecord]) -> [GachaRecord] {
        records.sorted(by: isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: GachaRecord, _ rhs: GachaRecord) -> Bool {
        if lhs.time != rhs.time {
            return lhs.time > rhs.time
        }

        let idComparison = compareRecordIDs(lhs.id, rhs.id)
        if idComparison != .orderedSame {
            return idComparison == .orderedDescending
        }
        if lhs.uid != rhs.uid {
            return (lhs.uid ?? "") > (rhs.uid ?? "")
        }
        if lhs.banner != rhs.banner {
            return lhs.banner.rawValue > rhs.banner.rawValue
        }
        if lhs.name != rhs.name {
            return lhs.name > rhs.name
        }
        return lhs.itemType > rhs.itemType
    }

    private static func compareRecordIDs(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsDigits = normalizedDigits(lhs)
        let rhsDigits = normalizedDigits(rhs)
        if let lhsDigits, let rhsDigits {
            if lhsDigits.count != rhsDigits.count {
                return lhsDigits.count < rhsDigits.count ? .orderedAscending : .orderedDescending
            }
            if lhsDigits != rhsDigits {
                return lhsDigits < rhsDigits ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        }
        return lhs.compare(rhs, options: [.literal])
    }

    private static func normalizedDigits(_ value: String) -> String? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else {
            return nil
        }
        let normalized = value.drop(while: { $0 == "0" })
        return normalized.isEmpty ? "0" : String(normalized)
    }
}

struct GachaSummary: Equatable {
    var totalPulls: Int
    var fiveStarCount: Int
    var fourStarCount: Int
    var activityPity: Int
    var standardPity: Int

    var pitySinceLastFiveStar: Int { activityPity }

    init(
        totalPulls: Int,
        fiveStarCount: Int,
        fourStarCount: Int,
        activityPity: Int,
        standardPity: Int
    ) {
        self.totalPulls = totalPulls
        self.fiveStarCount = fiveStarCount
        self.fourStarCount = fourStarCount
        self.activityPity = activityPity
        self.standardPity = standardPity
    }

    init(totalPulls: Int, fiveStarCount: Int, fourStarCount: Int, pitySinceLastFiveStar: Int) {
        self.init(
            totalPulls: totalPulls,
            fiveStarCount: fiveStarCount,
            fourStarCount: fourStarCount,
            activityPity: pitySinceLastFiveStar,
            standardPity: 0
        )
    }

    static func make(from records: [GachaRecord]) -> GachaSummary {
        let activityRecords = GachaRecord.sortedNewestFirst(records.filter { GachaPool.activity.contains($0.banner) })
        let standardRecords = GachaRecord.sortedNewestFirst(records.filter { GachaPool.standard.contains($0.banner) })
        return GachaSummary(
            totalPulls: records.count,
            fiveStarCount: records.filter { $0.rarity == 5 }.count,
            fourStarCount: records.filter { $0.rarity == 4 }.count,
            activityPity: activityRecords.firstIndex { $0.rarity == 5 } ?? activityRecords.count,
            standardPity: standardRecords.firstIndex { $0.rarity == 5 } ?? standardRecords.count
        )
    }
}
