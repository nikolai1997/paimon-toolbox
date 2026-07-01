import XCTest
@testable import PaimonToolbox

final class GachaDashboardLayoutTests: XCTestCase {
    func testDefaultOrderIncludesRecordsLast() {
        XCTAssertEqual(
            GachaDashboardLayout.defaultOrder,
            [.insights, .rarityDistribution, .bannerDistribution, .monthlyTrend, .bannerPity, .recentFiveStars, .recordDetails]
        )
    }

    func testStoredOrderIsNormalizedWithMissingAndUnknownModules() {
        let encoded = "recentFiveStars,unknown,insights"

        let modules = GachaDashboardLayout.modules(from: encoded)

        XCTAssertEqual(
            modules,
            [.recentFiveStars, .insights, .rarityDistribution, .bannerDistribution, .monthlyTrend, .bannerPity, .recordDetails]
        )
    }

    func testLegacySplitModulesCollapseToInsights() {
        let encoded = "fiveStarRate,fourStarRate,averageFiveStarPity,latestFiveStar"
        let modules = GachaDashboardLayout.modules(from: encoded)

        XCTAssertEqual(
            modules,
            [.insights, .rarityDistribution, .bannerDistribution, .monthlyTrend, .bannerPity, .recentFiveStars, .recordDetails]
        )
    }

    func testMoveModuleBeforeTarget() {
        let moved = GachaDashboardLayout.move(
            .recordDetails,
            before: .rarityDistribution,
            in: GachaDashboardLayout.defaultOrder
        )

        XCTAssertEqual(
            moved,
            [.insights, .recordDetails, .rarityDistribution, .bannerDistribution, .monthlyTrend, .bannerPity, .recentFiveStars]
        )
    }

    func testMoveModuleToEnd() {
        let moved = GachaDashboardLayout.moveToEnd(
            .insights,
            in: GachaDashboardLayout.defaultOrder
        )

        XCTAssertEqual(
            moved,
            [.rarityDistribution, .bannerDistribution, .monthlyTrend, .bannerPity, .recentFiveStars, .recordDetails, .insights]
        )
    }
}
