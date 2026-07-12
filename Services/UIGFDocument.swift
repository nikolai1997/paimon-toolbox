import Foundation

enum GachaLogDocument {
    static func decodeRecords(from data: Data) throws -> [GachaRecord] {
        let nativeDecoder = JSONDecoder()
        nativeDecoder.dateDecodingStrategy = .iso8601
        if let records = try? nativeDecoder.decode([GachaRecord].self, from: data) {
            return records
        }

        let decoder = JSONDecoder()
        if let document = try? decoder.decode(UIGFV4Document.self, from: data), document.hk4e != nil {
            return GachaRecord.sortedNewestFirst(
                document.hk4e?.flatMap { account in
                    account.list.compactMap { item in
                        item.record(uid: account.uid, timeZone: account.timezone)
                    }
                } ?? []
            )
        }

        let document = try decoder.decode(LegacyUIGFDocument.self, from: data)
        let uid = document.info?.uid.flatMap { $0.isEmpty ? nil : $0 }
        return GachaRecord.sortedNewestFirst(document.list.compactMap { $0.record(uid: uid, timeZone: 8) })
    }

    static func encodeNativeRecords(_ records: [GachaRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    static func encodeUIGFRecords(
        _ records: [GachaRecord],
        appVersion: String = AppVersion.current
    ) throws -> Data {
        let groupedRecords = Dictionary(grouping: records) { record in
            record.uid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let accounts = groupedRecords.keys
        .sorted()
        .map { uid in
            UIGFV4Account(
                uid: uid,
                timezone: 8,
                lang: "zh-cn",
                list: GachaRecord.sortedNewestFirst(groupedRecords[uid] ?? []).map(UIGFV4Item.init(record:))
            )
        }
        let document = UIGFV4Document(
            info: UIGFV4Info(
                exportTimestamp: Int(Date().timeIntervalSince1970),
                exportApp: "派蒙工具箱",
                exportAppVersion: appVersion,
                version: "v4.0"
            ),
            hk4e: accounts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func mergedRecords(existing: [GachaRecord], imported: [GachaRecord]) -> [GachaRecord] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.dedupeKey, $0) })
        for record in imported {
            byID[record.dedupeKey] = record
        }
        return GachaRecord.sortedNewestFirst(Array(byID.values))
    }
}

private struct UIGFV4Document: Codable {
    var info: UIGFV4Info
    var hk4e: [UIGFV4Account]?
}

private struct UIGFV4Info: Codable {
    var exportTimestamp: Int
    var exportApp: String
    var exportAppVersion: String
    var version: String

    enum CodingKeys: String, CodingKey {
        case exportTimestamp = "export_timestamp"
        case exportApp = "export_app"
        case exportAppVersion = "export_app_version"
        case version
    }

    init(exportTimestamp: Int, exportApp: String, exportAppVersion: String, version: String) {
        self.exportTimestamp = exportTimestamp
        self.exportApp = exportApp
        self.exportAppVersion = exportAppVersion
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .exportTimestamp) {
            exportTimestamp = value
        } else {
            let value = try container.decode(String.self, forKey: .exportTimestamp)
            exportTimestamp = Int(value) ?? 0
        }
        exportApp = try container.decode(String.self, forKey: .exportApp)
        exportAppVersion = try container.decode(String.self, forKey: .exportAppVersion)
        version = try container.decode(String.self, forKey: .version)
    }
}

private struct UIGFV4Account: Codable {
    var uid: String
    var timezone: Int
    var lang: String?
    var list: [UIGFV4Item]

    private enum CodingKeys: String, CodingKey {
        case uid
        case timezone
        case lang
        case list
    }

    init(uid: String, timezone: Int, lang: String?, list: [UIGFV4Item]) {
        self.uid = uid
        self.timezone = timezone
        self.lang = lang
        self.list = list
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .uid) {
            uid = value
        } else {
            uid = String(try container.decode(Int.self, forKey: .uid))
        }
        timezone = try container.decode(Int.self, forKey: .timezone)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        list = try container.decode([UIGFV4Item].self, forKey: .list)
    }
}

private struct UIGFV4Item: Codable {
    var id: String
    var itemID: String
    var count: String?
    var time: String
    var name: String?
    var itemType: String?
    var rankType: String?
    var gachaType: String
    var uigfGachaType: String

    enum CodingKeys: String, CodingKey {
        case id
        case itemID = "item_id"
        case count
        case time
        case name
        case itemType = "item_type"
        case rankType = "rank_type"
        case gachaType = "gacha_type"
        case uigfGachaType = "uigf_gacha_type"
    }

    init(record: GachaRecord) {
        id = record.id
        itemID = record.itemID ?? ""
        count = "1"
        time = DateFormatter.uigf(timeZoneHours: 8).string(from: record.time)
        name = record.name
        itemType = record.itemType
        rankType = String(record.rarity)
        gachaType = record.banner.gachaTypeCode
        uigfGachaType = record.banner.uigfPityTypeCode
    }

    func record(uid: String?, timeZone: Int) -> GachaRecord? {
        guard let date = DateFormatter.uigf(timeZoneHours: timeZone).date(from: time) else { return nil }
        return GachaRecord(
            uid: uid.flatMap { $0.isEmpty ? nil : $0 },
            itemID: itemID.isEmpty ? nil : itemID,
            id: id,
            time: date,
            banner: BannerKind(gachaType: gachaType, uigfGachaType: uigfGachaType),
            name: name ?? itemID,
            itemType: itemType ?? "",
            rarity: Int(rankType ?? "") ?? 3
        )
    }
}

private struct LegacyUIGFDocument: Codable {
    var info: LegacyUIGFInfo?
    var list: [LegacyUIGFItem]
}

private struct LegacyUIGFInfo: Codable {
    var uid: String?
    var lang: String?
    var exportTime: String?
    var exportTimestamp: Int?
    var uigfVersion: String?

    enum CodingKeys: String, CodingKey {
        case uid
        case lang
        case exportTime = "export_time"
        case exportTimestamp = "export_timestamp"
        case uigfVersion = "uigf_version"
    }
}

private struct LegacyUIGFItem: Codable {
    var id: String
    var itemID: String?
    var time: String
    var name: String
    var itemType: String
    var rankType: String
    var gachaType: String?
    var uigfGachaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case itemID = "item_id"
        case time
        case name
        case itemType = "item_type"
        case rankType = "rank_type"
        case gachaType = "gacha_type"
        case uigfGachaType = "uigf_gacha_type"
    }

    func record(uid: String?, timeZone: Int) -> GachaRecord? {
        guard let date = DateFormatter.uigf(timeZoneHours: timeZone).date(from: time) ?? ISO8601DateFormatter().date(from: time) else {
            return nil
        }
        return GachaRecord(
            uid: uid,
            itemID: itemID,
            id: id.isEmpty ? stableID : id,
            time: date,
            banner: BannerKind(gachaType: gachaType, uigfGachaType: uigfGachaType),
            name: name,
            itemType: itemType,
            rarity: Int(rankType) ?? 3
        )
    }

    private var stableID: String {
        [time, name, itemType, rankType, gachaType ?? "", uigfGachaType ?? ""].joined(separator: "|")
    }
}

private extension DateFormatter {
    static func uigf(timeZoneHours: Int) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: timeZoneHours * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private extension BannerKind {
    init(gachaType: String?, uigfGachaType: String?) {
        switch gachaType ?? uigfGachaType {
        case "400": self = .characterEvent2
        case "302": self = .weapon
        case "500": self = .chronicled
        case "200": self = .standard
        default: self = .character
        }
    }

    var gachaTypeCode: String {
        switch self {
        case .character: "301"
        case .characterEvent2: "400"
        case .weapon: "302"
        case .chronicled: "500"
        case .standard: "200"
        }
    }

    var uigfPityTypeCode: String {
        switch self {
        case .character, .characterEvent2: "301"
        case .weapon: "302"
        case .chronicled: "500"
        case .standard: "200"
        }
    }
}

private extension GachaRecord {
    var dedupeKey: String {
        let owner = uid ?? "__unassigned__"
        let recordKey = id.isEmpty
            ? [time.ISO8601Format(), banner.rawValue, name, itemType, "\(rarity)"].joined(separator: "|")
            : id
        return "\(owner)|\(recordKey)"
    }
}
