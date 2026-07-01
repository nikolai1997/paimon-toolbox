import XCTest
@testable import PaimonToolbox

final class GlobalSearchIndexTests: XCTestCase {
    func testSearchFindsStaticInterfaceTermsAndRoutesToSections() {
        let results = GlobalSearchIndex.results(
            matching: "隐私声明",
            metadata: nil,
            gachaRecords: [],
            plans: []
        )

        XCTAssertEqual(results.first?.title, "隐私声明")
        XCTAssertEqual(results.first?.section, .settings)
    }

    func testSearchFindsMetadataGachaAndPlannerData() {
        let metadata = MetadataBundle(
            version: "test",
            updatedAt: Date(timeIntervalSince1970: 0),
            characters: [
                GameCharacter(
                    id: 10000002,
                    name: "神里绫华",
                    element: "冰",
                    weaponType: "单手剑",
                    rarity: 5,
                    region: "稻妻",
                    materials: ["绯樱绣球"]
                )
            ],
            weapons: [
                Weapon(
                    id: 11502,
                    name: "雾切之回光",
                    type: "单手剑",
                    rarity: 5,
                    stat: "暴击伤害",
                    materials: ["远海夷地的金枝"]
                )
            ],
            materials: [
                MaterialItem(
                    id: 2001,
                    name: "绯樱绣球",
                    category: "区域特产",
                    source: "稻妻野外采集"
                )
            ]
        )
        let records = [
            GachaRecord(
                id: "1",
                time: Date(timeIntervalSince1970: 0),
                banner: .character,
                name: "神里绫华",
                itemType: "角色",
                rarity: 5
            )
        ]
        let plans = [
            CultivationPlan(
                id: UUID(),
                targetName: "神里绫华",
                targetKind: "角色",
                currentLevel: 1,
                targetLevel: 90,
                requirements: [
                    MaterialRequirement(id: "m1", materialName: "绯樱绣球", required: 168, owned: 20)
                ]
            )
        ]

        let ayakaResults = GlobalSearchIndex.results(
            matching: "神里",
            metadata: metadata,
            gachaRecords: records,
            plans: plans
        )
        let sakuraResults = GlobalSearchIndex.results(
            matching: "绯樱",
            metadata: metadata,
            gachaRecords: records,
            plans: plans
        )

        XCTAssertTrue(ayakaResults.contains { $0.title == "神里绫华" && $0.section == .database })
        XCTAssertTrue(ayakaResults.contains { $0.title == "神里绫华" && $0.section == .gachaLog })
        XCTAssertTrue(ayakaResults.contains { $0.title == "神里绫华" && $0.section == .planner })
        XCTAssertTrue(sakuraResults.contains { $0.title == "绯樱绣球" && $0.section == .database })
        XCTAssertTrue(sakuraResults.contains { $0.title == "神里绫华" && $0.section == .planner })
    }

    func testBlankSearchReturnsNoResults() {
        let results = GlobalSearchIndex.results(
            matching: "   ",
            metadata: nil,
            gachaRecords: [],
            plans: []
        )

        XCTAssertTrue(results.isEmpty)
    }
}
