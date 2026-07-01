import Foundation

struct OverviewData: Equatable {
    var latest: RemoteLatestInfo?
    var announcements: [AnnouncementItem]
    var gachaEvents: [GachaEventInfo]

    static let empty = OverviewData(latest: nil, announcements: [], gachaEvents: [])
}

struct RemoteLatestInfo: Codable, Equatable {
    var schemaVersion: Int
    var dataVersion: String
    var updatedAt: Date
    var notes: String
    var required: Bool
}

struct AnnouncementFeed: Codable, Equatable {
    var schemaVersion: Int
    var updatedAt: Date
    var items: [AnnouncementItem]
}

struct AnnouncementItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var url: URL?
    var bannerURL: URL?
    var startsAt: Date?
    var endsAt: Date?
    var typeLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case url
        case bannerURL = "banner"
        case startsAt
        case endsAt
        case typeLabel
    }
}

struct GachaEventInfo: Codable, Identifiable, Equatable {
    var id: String { "\(type)-\(name)-\(from.timeIntervalSince1970)" }
    var name: String
    var type: Int
    var version: String
    var from: Date
    var to: Date
    var bannerURL: URL?
    var upOrangeList: [Int]
    var upPurpleList: [Int]

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case version
        case from
        case to
        case bannerURL = "banner"
        case upOrangeList
        case upPurpleList
    }

    var typeTitle: String {
        switch type {
        case 301:
            "角色活动祈愿"
        case 400:
            "角色活动祈愿-2"
        case 302:
            "武器活动祈愿"
        case 500:
            "集录祈愿"
        default:
            "祈愿活动"
        }
    }
}

struct OverviewPlanHighlight: Equatable, Identifiable {
    var id: CultivationPlan.ID
    var targetName: String
    var targetKind: String
    var completion: Double
    var completionText: String
}

struct RerunTimerEntry: Equatable, Identifiable {
    var id: String { "\(kind)-\(itemID)" }
    var itemID: Int
    var kind: String
    var name: String
    var iconURL: URL?
    var lastAppearedAt: Date
    var lastBannerName: String
    var version: String
    var daysSinceLastAppearance: Int

    var daysText: String {
        if daysSinceLastAppearance == 0 {
            return "进行中"
        }
        return "\(daysSinceLastAppearance) 天"
    }
}

enum OverviewSummary {
    private static let standardCharacterIDs: Set<Int> = [
        10000003, // 琴
        10000016, // 迪卢克
        10000035, // 七七
        10000041, // 莫娜
        10000042, // 刻晴
        10000069, // 提纳里
        10000079, // 迪希雅
        10000109  // 梦见月瑞希
    ]

    static func activeGachaEvents(from events: [GachaEventInfo], now: Date = Date()) -> [GachaEventInfo] {
        events
            .filter { $0.from <= now && now <= $0.to }
            .sorted { lhs, rhs in
                if lhs.type != rhs.type {
                    return lhs.type < rhs.type
                }
                return lhs.from < rhs.from
            }
    }

    static func characterRerunTimers(
        from events: [GachaEventInfo],
        characters: [GameCharacter],
        now: Date = Date(),
        limit: Int = 5
    ) -> [RerunTimerEntry] {
        let charactersByID = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })

        return rerunTimers(
            from: events.filter { $0.type != 302 },
            itemIDs: { $0.upOrangeList },
            itemInfo: { id in
                guard let character = charactersByID[id],
                      character.rarity == 5,
                      !standardCharacterIDs.contains(id) else {
                    return nil
                }
                return (character.name, character.iconURL ?? character.portraitURL)
            },
            kind: "character",
            now: now,
            limit: limit
        )
    }

    static func weaponRerunTimers(
        from events: [GachaEventInfo],
        weapons: [Weapon],
        now: Date = Date(),
        limit: Int = 5
    ) -> [RerunTimerEntry] {
        let weaponsByID = Dictionary(uniqueKeysWithValues: weapons.map { ($0.id, $0) })

        return rerunTimers(
            from: events.filter { $0.type == 302 },
            itemIDs: { $0.upOrangeList },
            itemInfo: { id in
                guard let weapon = weaponsByID[id], weapon.rarity == 5 else {
                    return nil
                }
                return (weapon.name, weapon.iconURL)
            },
            kind: "weapon",
            now: now,
            limit: limit
        )
    }

    static func planHighlights(from plans: [CultivationPlan], limit: Int = 2) -> [OverviewPlanHighlight] {
        plans
            .filter { $0.completion < 1 }
            .sorted { lhs, rhs in
                if lhs.completion != rhs.completion {
                    return lhs.completion > rhs.completion
                }
                return lhs.targetName < rhs.targetName
            }
            .prefix(limit)
            .map {
                OverviewPlanHighlight(
                    id: $0.id,
                    targetName: $0.targetName,
                    targetKind: $0.targetKind,
                    completion: $0.completion,
                    completionText: AppFormatters.percentString($0.completion)
                )
            }
    }

    private static func rerunTimers(
        from events: [GachaEventInfo],
        itemIDs: (GachaEventInfo) -> [Int],
        itemInfo: (Int) -> (name: String, iconURL: URL?)?,
        kind: String,
        now: Date,
        limit: Int
    ) -> [RerunTimerEntry] {
        var latestEventByItemID: [Int: GachaEventInfo] = [:]

        for event in events where event.from <= now {
            for itemID in itemIDs(event) {
                guard itemInfo(itemID) != nil else {
                    continue
                }

                if let current = latestEventByItemID[itemID], current.to >= event.to {
                    continue
                }
                latestEventByItemID[itemID] = event
            }
        }

        return latestEventByItemID.compactMap { itemID, event in
            guard let info = itemInfo(itemID) else {
                return nil
            }

            let days = max(0, Calendar.current.dateComponents([.day], from: event.to, to: now).day ?? 0)
            return RerunTimerEntry(
                itemID: itemID,
                kind: kind,
                name: info.name,
                iconURL: info.iconURL,
                lastAppearedAt: event.to,
                lastBannerName: event.name,
                version: event.version,
                daysSinceLastAppearance: days
            )
        }
        .sorted { lhs, rhs in
            if lhs.daysSinceLastAppearance != rhs.daysSinceLastAppearance {
                return lhs.daysSinceLastAppearance > rhs.daysSinceLastAppearance
            }
            return lhs.name < rhs.name
        }
        .prefix(limit)
        .map { $0 }
    }
}
