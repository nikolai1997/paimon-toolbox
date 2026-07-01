import XCTest
@testable import PaimonToolbox

final class GachaAnalysisTests: XCTestCase {
    func testRarityAndBannerBreakdownCountsRecords() {
        let records = [
            Self.record(id: "1", day: 1, banner: .character, name: "冷刃", itemType: "武器", rarity: 3),
            Self.record(id: "2", day: 2, banner: .character, name: "夏洛蒂", itemType: "角色", rarity: 4),
            Self.record(id: "3", day: 3, banner: .weapon, name: "祭礼弓", itemType: "武器", rarity: 4),
            Self.record(id: "4", day: 4, banner: .standard, name: "迪卢克", itemType: "角色", rarity: 5)
        ]

        let analysis = GachaAnalysis.make(from: records)

        XCTAssertEqual(analysis.rarityBreakdown.map(\.rarity), [5, 4, 3])
        XCTAssertEqual(analysis.rarityBreakdown.map(\.count), [1, 2, 1])
        XCTAssertEqual(analysis.bannerBreakdown.map(\.banner), [.character, .characterEvent2, .weapon, .chronicled, .standard])
        XCTAssertEqual(analysis.bannerBreakdown.map(\.count), [2, 0, 1, 0, 1])
        XCTAssertEqual(analysis.fiveStarRateText, "25.0%")
    }

    func testBannerPityAndFiveStarIntervalsUseEachBannerIndependently() {
        let records = [
            Self.record(id: "1", day: 1, banner: .character, name: "三星 1", itemType: "武器", rarity: 3),
            Self.record(id: "2", day: 2, banner: .character, name: "五星 A", itemType: "角色", rarity: 5),
            Self.record(id: "3", day: 3, banner: .weapon, name: "四星 W", itemType: "武器", rarity: 4),
            Self.record(id: "4", day: 4, banner: .character, name: "三星 2", itemType: "武器", rarity: 3),
            Self.record(id: "5", day: 5, banner: .character, name: "三星 3", itemType: "武器", rarity: 3),
            Self.record(id: "6", day: 6, banner: .character, name: "五星 B", itemType: "角色", rarity: 5),
            Self.record(id: "7", day: 7, banner: .character, name: "三星 4", itemType: "武器", rarity: 3)
        ]

        let analysis = GachaAnalysis.make(from: records)

        let characterBanner = analysis.bannerStats.first { $0.banner == .character }
        XCTAssertEqual(characterBanner?.currentPity, 1)
        XCTAssertEqual(characterBanner?.fiveStarCount, 2)
        XCTAssertEqual(characterBanner?.averageFiveStarPity, 3)
        XCTAssertEqual(analysis.recentFiveStars.map(\.name), ["五星 B", "五星 A"])
        XCTAssertEqual(analysis.recentFiveStars.map(\.pullsSincePreviousFiveStar), [3, 2])
    }

    func testMonthlyTrendGroupsByMonthChronologically() {
        let records = [
            Self.record(id: "1", month: 4, day: 30, banner: .character, name: "四星", itemType: "角色", rarity: 4),
            Self.record(id: "2", month: 5, day: 1, banner: .character, name: "五星", itemType: "角色", rarity: 5),
            Self.record(id: "3", month: 5, day: 2, banner: .weapon, name: "三星", itemType: "武器", rarity: 3)
        ]

        let analysis = GachaAnalysis.make(from: records)

        XCTAssertEqual(analysis.monthlyTrend.map(\.monthLabel), ["2026-04", "2026-05"])
        XCTAssertEqual(analysis.monthlyTrend.map(\.count), [1, 2])
        XCTAssertEqual(analysis.monthlyTrend.map(\.fiveStarCount), [0, 1])
    }

    private static func record(
        id: String,
        month: Int = 6,
        day: Int,
        banner: BannerKind,
        name: String,
        itemType: String,
        rarity: Int
    ) -> GachaRecord {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = 12
        return GachaRecord(
            id: id,
            time: components.date!,
            banner: banner,
            name: name,
            itemType: itemType,
            rarity: rarity
        )
    }
}
