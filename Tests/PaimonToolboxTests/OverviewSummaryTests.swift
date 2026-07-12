import XCTest
@testable import PaimonToolbox

final class OverviewSummaryTests: XCTestCase {
    func testActiveGachaEventsOnlyIncludesEventsOpenAtReferenceDate() {
        let referenceDate = Date(timeIntervalSince1970: 1_782_345_600)
        let activeCharacter = makeEvent(
            name: "霜锋夜白",
            type: 301,
            from: referenceDate.addingTimeInterval(-3_600),
            to: referenceDate.addingTimeInterval(3_600)
        )
        let expired = makeEvent(
            name: "杯装之诗",
            type: 301,
            from: referenceDate.addingTimeInterval(-7_200),
            to: referenceDate.addingTimeInterval(-3_600)
        )
        let activeWeapon = makeEvent(
            name: "神铸赋形",
            type: 302,
            from: referenceDate.addingTimeInterval(-3_600),
            to: referenceDate.addingTimeInterval(7_200)
        )

        let result = OverviewSummary.activeGachaEvents(
            from: [expired, activeWeapon, activeCharacter],
            now: referenceDate
        )

        XCTAssertEqual(result.map(\.name), ["霜锋夜白", "神铸赋形"])
    }

    func testActiveGachaEventsDeduplicatesEquivalentBannersBeforeDisplayLimit() {
        let referenceDate = Date(timeIntervalSince1970: 1_783_785_600)
        let officialMirror = makeEvent(
            name: "镜中的茶宴",
            type: 301,
            version: "月之八",
            from: referenceDate.addingTimeInterval(-7_200),
            to: referenceDate.addingTimeInterval(7_200)
        )
        let snapMirror = makeEvent(
            name: "镜中的茶宴",
            type: 301,
            version: "6.7",
            from: referenceDate.addingTimeInterval(-3_600),
            to: referenceDate.addingTimeInterval(7_200),
            bannerURL: URL(string: "https://example.com/mirror.jpg"),
            upOrangeList: [10002001],
            upPurpleList: [1, 2, 3]
        )
        let starryNight = makeEvent(
            name: "星边夜语",
            type: 400,
            from: referenceDate.addingTimeInterval(-3_600),
            to: referenceDate.addingTimeInterval(7_200)
        )
        let weapon = makeEvent(
            name: "神铸赋形",
            type: 302,
            from: referenceDate.addingTimeInterval(-3_600),
            to: referenceDate.addingTimeInterval(7_200)
        )

        let result = OverviewSummary.activeGachaEvents(
            from: [officialMirror, snapMirror, starryNight, weapon],
            now: referenceDate
        )

        XCTAssertEqual(result.map(\.name), ["镜中的茶宴", "神铸赋形", "星边夜语"])
        XCTAssertEqual(result.first?.version, "6.7")
    }

    func testPlanHighlightsSortIncompletePlansByHighestCompletion() {
        let nearlyDone = makePlan(name: "芙宁娜", owned: 9, required: 10)
        let complete = makePlan(name: "那维莱特", owned: 10, required: 10)
        let started = makePlan(name: "玛薇卡", owned: 3, required: 10)

        let result = OverviewSummary.planHighlights(
            from: [started, complete, nearlyDone],
            limit: 2
        )

        XCTAssertEqual(result.map(\.targetName), ["芙宁娜", "玛薇卡"])
        XCTAssertEqual(result.map(\.completionText), ["90%", "30%"])
    }

    func testCharacterRerunTimersExcludeStandardFiveStarCharacters() {
        let referenceDate = Date(timeIntervalSince1970: 1_782_345_600)
        let mizuki = makeCharacter(id: 10000109, name: "梦见月瑞希", rarity: 5)
        let huTao = makeCharacter(id: 10000046, name: "胡桃", rarity: 5)
        let mizukiEvent = makeEvent(
            name: "浮枕朝颜",
            type: 301,
            from: referenceDate.addingTimeInterval(-200_000),
            to: referenceDate.addingTimeInterval(-190_000),
            upOrangeList: [mizuki.id]
        )
        let huTaoEvent = makeEvent(
            name: "赤团开时",
            type: 400,
            from: referenceDate.addingTimeInterval(-300_000),
            to: referenceDate.addingTimeInterval(-290_000),
            upOrangeList: [huTao.id]
        )

        let result = OverviewSummary.characterRerunTimers(
            from: [mizukiEvent, huTaoEvent],
            characters: [mizuki, huTao],
            now: referenceDate,
            limit: 10
        )

        XCTAssertEqual(result.map(\.name), ["胡桃"])
    }

    private func makeEvent(
        name: String,
        type: Int,
        version: String = "6.6",
        from: Date,
        to: Date,
        bannerURL: URL? = nil,
        upOrangeList: [Int] = [],
        upPurpleList: [Int] = []
    ) -> GachaEventInfo {
        GachaEventInfo(
            name: name,
            type: type,
            version: version,
            from: from,
            to: to,
            bannerURL: bannerURL,
            upOrangeList: upOrangeList,
            upPurpleList: upPurpleList
        )
    }

    private func makeCharacter(id: Int, name: String, rarity: Int) -> GameCharacter {
        GameCharacter(
            id: id,
            name: name,
            element: "风",
            weaponType: "法器",
            rarity: rarity,
            region: "稻妻",
            materials: []
        )
    }

    private func makePlan(name: String, owned: Int, required: Int) -> CultivationPlan {
        CultivationPlan(
            id: UUID(),
            targetName: name,
            targetKind: "角色",
            currentLevel: 1,
            targetLevel: 90,
            requirements: [
                MaterialRequirement(id: "\(name)-材料", materialName: "材料", required: required, owned: owned)
            ]
        )
    }
}
