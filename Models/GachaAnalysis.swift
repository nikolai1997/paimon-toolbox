import Foundation

struct GachaAnalysis: Equatable {
    var totalPulls: Int
    var fiveStarRate: Double
    var fourStarRate: Double
    var rarityBreakdown: [GachaRarityBreakdown]
    var bannerBreakdown: [GachaBannerBreakdown]
    var bannerStats: [GachaBannerStat]
    var monthlyTrend: [GachaMonthlyTrend]
    var recentFiveStars: [GachaFiveStarHit]

    var fiveStarRateText: String {
        Self.percentFormatter.string(from: NSNumber(value: fiveStarRate)) ?? "0.0%"
    }

    var fourStarRateText: String {
        Self.percentFormatter.string(from: NSNumber(value: fourStarRate)) ?? "0.0%"
    }

    var averageFiveStarPityText: String {
        let hits = recentFiveStarIntervals
        guard !hits.isEmpty else {
            return "--"
        }
        let average = Double(hits.reduce(0, +)) / Double(hits.count)
        return "\(Int(average.rounded())) 抽"
    }

    private var recentFiveStarIntervals: [Int] {
        bannerStats.flatMap(\.fiveStarIntervals)
    }

    static func make(from records: [GachaRecord]) -> GachaAnalysis {
        let sortedNewest = GachaRecord.sortedNewestFirst(records)
        let total = records.count
        let fiveStarCount = records.filter { $0.rarity == 5 }.count
        let fourStarCount = records.filter { $0.rarity == 4 }.count

        return GachaAnalysis(
            totalPulls: total,
            fiveStarRate: total == 0 ? 0 : Double(fiveStarCount) / Double(total),
            fourStarRate: total == 0 ? 0 : Double(fourStarCount) / Double(total),
            rarityBreakdown: rarityBreakdown(from: records, total: total),
            bannerBreakdown: bannerBreakdown(from: records, total: total),
            bannerStats: GachaPool.allCases.map { bannerStat(for: $0, in: records) },
            monthlyTrend: monthlyTrend(from: records),
            recentFiveStars: recentFiveStars(from: sortedNewest)
        )
    }

    private static func rarityBreakdown(from records: [GachaRecord], total: Int) -> [GachaRarityBreakdown] {
        [5, 4, 3].map { rarity in
            let count = records.filter { $0.rarity == rarity }.count
            return GachaRarityBreakdown(
                rarity: rarity,
                count: count,
                ratio: total == 0 ? 0 : Double(count) / Double(total)
            )
        }
    }

    private static func bannerBreakdown(from records: [GachaRecord], total: Int) -> [GachaBannerBreakdown] {
        BannerKind.allCases.map { banner in
            let count = records.filter { $0.banner == banner }.count
            return GachaBannerBreakdown(
                banner: banner,
                count: count,
                ratio: total == 0 ? 0 : Double(count) / Double(total)
            )
        }
    }

    private static func bannerStat(for pool: GachaPool, in records: [GachaRecord]) -> GachaBannerStat {
        let bannerRecords = GachaRecord.sortedNewestFirst(records.filter { pool.contains($0.banner) })
        let fiveStarHits = fiveStarHits(for: bannerRecords)
        let averagePity: Int?
        if fiveStarHits.isEmpty {
            averagePity = nil
        } else {
            averagePity = Int((Double(fiveStarHits.map(\.pullsSincePreviousFiveStar).reduce(0, +)) / Double(fiveStarHits.count)).rounded())
        }

        return GachaBannerStat(
            banner: pool.representativeBanner,
            count: bannerRecords.count,
            fiveStarCount: bannerRecords.filter { $0.rarity == 5 }.count,
            fourStarCount: bannerRecords.filter { $0.rarity == 4 }.count,
            currentPity: bannerRecords.firstIndex { $0.rarity == 5 } ?? bannerRecords.count,
            averageFiveStarPity: averagePity,
            fiveStarIntervals: fiveStarHits.map(\.pullsSincePreviousFiveStar)
        )
    }

    private static func monthlyTrend(from records: [GachaRecord]) -> [GachaMonthlyTrend] {
        let calendar = Calendar.gachaAnalysis
        let grouped = Dictionary(grouping: records) { record in
            let components = calendar.dateComponents([.year, .month], from: record.time)
            return GachaMonthKey(year: components.year ?? 1970, month: components.month ?? 1)
        }

        return grouped.keys.sorted().map { key in
            let records = grouped[key] ?? []
            return GachaMonthlyTrend(
                monthLabel: String(format: "%04d-%02d", key.year, key.month),
                count: records.count,
                fiveStarCount: records.filter { $0.rarity == 5 }.count,
                fourStarCount: records.filter { $0.rarity == 4 }.count
            )
        }
    }

    private static func recentFiveStars(from sortedNewest: [GachaRecord]) -> [GachaFiveStarHit] {
        GachaPool.allCases.flatMap { pool in
            fiveStarHits(for: sortedNewest.filter { pool.contains($0.banner) })
        }
        .sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time > rhs.time }
            return lhs.id > rhs.id
        }
        .prefix(8)
        .map(\.self)
    }

    private static func fiveStarHits(for sortedNewest: [GachaRecord]) -> [GachaFiveStarHit] {
        let chronological = sortedNewest.reversed()
        var pullCount = 0
        var result: [GachaFiveStarHit] = []
        for record in chronological {
            pullCount += 1
            if record.rarity == 5 {
                result.append(
                    GachaFiveStarHit(
                        id: record.id,
                        name: record.name,
                        banner: record.banner,
                        time: record.time,
                        pullsSincePreviousFiveStar: pullCount
                    )
                )
                pullCount = 0
            }
        }
        return result.sorted { $0.time > $1.time }
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

struct GachaRarityBreakdown: Identifiable, Equatable {
    var id: Int { rarity }
    var rarity: Int
    var count: Int
    var ratio: Double

    var title: String {
        "\(rarity) 星"
    }
}

struct GachaBannerBreakdown: Identifiable, Equatable {
    var id: BannerKind { banner }
    var banner: BannerKind
    var count: Int
    var ratio: Double
}

struct GachaBannerStat: Identifiable, Equatable {
    var id: BannerKind { banner }
    var banner: BannerKind
    var count: Int
    var fiveStarCount: Int
    var fourStarCount: Int
    var currentPity: Int
    var averageFiveStarPity: Int?
    var fiveStarIntervals: [Int] = []
}

struct GachaMonthlyTrend: Identifiable, Equatable {
    var id: String { monthLabel }
    var monthLabel: String
    var count: Int
    var fiveStarCount: Int
    var fourStarCount: Int
}

struct GachaFiveStarHit: Identifiable, Equatable {
    var id: String
    var name: String
    var banner: BannerKind
    var time: Date
    var pullsSincePreviousFiveStar: Int
}

private struct GachaMonthKey: Comparable, Hashable {
    var year: Int
    var month: Int

    static func < (lhs: GachaMonthKey, rhs: GachaMonthKey) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        return lhs.month < rhs.month
    }
}

private extension Calendar {
    static let gachaAnalysis: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        return calendar
    }()
}
