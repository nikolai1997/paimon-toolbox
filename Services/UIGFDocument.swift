import Foundation

enum GachaLogDocument {
    static func decodeRecords(from data: Data) throws -> [GachaRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let records = try? decoder.decode([GachaRecord].self, from: data) {
            return records
        }

        let document = try JSONDecoder().decode(UIGFDocument.self, from: data)
        return document.list.compactMap { item in
            guard let time = item.date else { return nil }
            return GachaRecord(
                id: item.id.isEmpty ? item.stableID : item.id,
                time: time,
                banner: BannerKind(uigfGachaType: item.uigfGachaType ?? item.gachaType),
                name: item.name,
                itemType: item.itemType,
                rarity: Int(item.rankType) ?? 3
            )
        }
    }

    static func encodeNativeRecords(_ records: [GachaRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    static func encodeUIGFRecords(_ records: [GachaRecord]) throws -> Data {
        let formatter = DateFormatter.uigf
        let document = UIGFDocument(
            info: UIGFInfo(
                uid: "",
                lang: "zh-cn",
                exportTime: formatter.string(from: Date()),
                exportTimestamp: Int(Date().timeIntervalSince1970),
                uigfVersion: "v4.0"
            ),
            list: records.sorted { $0.time > $1.time }.map { record in
                UIGFItem(
                    id: record.id,
                    time: formatter.string(from: record.time),
                    name: record.name,
                    itemType: record.itemType,
                    rankType: "\(record.rarity)",
                    gachaType: record.banner.uigfCode,
                    uigfGachaType: record.banner.uigfCode
                )
            }
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
        return byID.values.sorted { lhs, rhs in
            if lhs.time != rhs.time {
                return lhs.time > rhs.time
            }
            return lhs.id < rhs.id
        }
    }
}

private struct UIGFDocument: Codable {
    var info: UIGFInfo?
    var list: [UIGFItem]
}

private struct UIGFInfo: Codable {
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

private struct UIGFItem: Codable {
    var id: String
    var time: String
    var name: String
    var itemType: String
    var rankType: String
    var gachaType: String?
    var uigfGachaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case time
        case name
        case itemType = "item_type"
        case rankType = "rank_type"
        case gachaType = "gacha_type"
        case uigfGachaType = "uigf_gacha_type"
    }

    var date: Date? {
        DateFormatter.uigf.date(from: time) ?? ISO8601DateFormatter().date(from: time)
    }

    var stableID: String {
        [time, name, itemType, rankType, gachaType ?? "", uigfGachaType ?? ""].joined(separator: "|")
    }
}

private extension DateFormatter {
    static let uigf: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension BannerKind {
    init(uigfGachaType: String?) {
        switch uigfGachaType {
        case "400": self = .characterEvent2
        case "302": self = .weapon
        case "500": self = .chronicled
        case "200": self = .standard
        default: self = .character
        }
    }

    var uigfCode: String {
        switch self {
        case .character: "301"
        case .characterEvent2: "400"
        case .weapon: "302"
        case .chronicled: "500"
        case .standard: "200"
        }
    }
}

private extension GachaRecord {
    var dedupeKey: String {
        id.isEmpty ? [time.ISO8601Format(), banner.rawValue, name, itemType, "\(rarity)"].joined(separator: "|") : id
    }
}
