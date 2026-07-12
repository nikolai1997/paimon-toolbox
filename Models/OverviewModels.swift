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

    private enum OfficialCodingKeys: String, CodingKey {
        case contentURL
        case startTime
        case endTime
        case type
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        url: URL?,
        bannerURL: URL?,
        startsAt: Date?,
        endsAt: Date?,
        typeLabel: String?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.bannerURL = bannerURL
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.typeLabel = typeLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let officialContainer = try decoder.container(keyedBy: OfficialCodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        url = Self.decodeOptionalURL(from: container, keys: [.url])
            ?? Self.decodeOptionalURL(from: officialContainer, keys: [.contentURL])
        bannerURL = Self.decodeOptionalURL(from: container, keys: [.bannerURL])
        startsAt = Self.decodeOptionalDate(from: container, keys: [.startsAt])
            ?? Self.decodeOptionalDate(from: officialContainer, keys: [.startTime])
        endsAt = Self.decodeOptionalDate(from: container, keys: [.endsAt])
            ?? Self.decodeOptionalDate(from: officialContainer, keys: [.endTime])
        typeLabel = Self.decodeOptionalString(from: container, keys: [.typeLabel])
            ?? Self.decodeOptionalString(from: officialContainer, keys: [.type])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(bannerURL, forKey: .bannerURL)
        try container.encodeIfPresent(startsAt, forKey: .startsAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encodeIfPresent(typeLabel, forKey: .typeLabel)
    }

    private static func decodeOptionalURL<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> URL? {
        for key in keys {
            guard let rawValue = try? container.decode(String.self, forKey: key) else {
                continue
            }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host,
                  !host.isEmpty else {
                continue
            }
            return url
        }
        return nil
    }

    private static func decodeOptionalString<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> String? {
        for key in keys {
            guard let rawValue = try? container.decode(String.self, forKey: key) else {
                continue
            }
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func decodeOptionalDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        keys: [Key]
    ) -> Date? {
        for key in keys {
            if let date = try? container.decode(Date.self, forKey: key) {
                return date
            }
            guard let value = try? container.decode(String.self, forKey: key) else {
                continue
            }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
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
    private struct ActiveGachaIdentity: Hashable {
        var type: Int
        var name: String
    }

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
        var uniqueEvents: [ActiveGachaIdentity: GachaEventInfo] = [:]

        for event in events where event.from <= now && now <= event.to {
            let identity = ActiveGachaIdentity(type: event.type, name: event.name)
            if let existing = uniqueEvents[identity],
               gachaEventCompleteness(existing) >= gachaEventCompleteness(event) {
                continue
            }
            uniqueEvents[identity] = event
        }

        return uniqueEvents.values.sorted { lhs, rhs in
            if lhs.type != rhs.type {
                return lhs.type < rhs.type
            }
            return lhs.from < rhs.from
        }
    }

    private static func gachaEventCompleteness(_ event: GachaEventInfo) -> Int {
        (event.upOrangeList.isEmpty ? 0 : 1)
            + (event.upPurpleList.isEmpty ? 0 : 1)
            + (event.bannerURL == nil ? 0 : 1)
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
