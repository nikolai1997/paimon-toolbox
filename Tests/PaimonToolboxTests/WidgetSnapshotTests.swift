import XCTest
@testable import PaimonToolbox

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotMapsSignInGachaAndPlannerData() {
        let account = LocalAccountStatus(
            isSignedIn: true,
            nickname: "旅行者",
            accountID: "10001",
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "荧", level: 60, isSelected: true),
            signInSummary: SignInSummary(uid: "100000001", month: 6, totalSignDay: 12, isTodaySigned: false, rewards: []),
            sessionMessage: nil,
            lastCheckInDate: nil
        )
        let records = [
            record(id: "1", day: 1, banner: .character, name: "冷刃", itemType: "武器", rarity: 3),
            record(id: "2", day: 2, banner: .character, name: "神里绫华", itemType: "角色", rarity: 5),
            record(id: "3", day: 3, banner: .weapon, name: "祭礼剑", itemType: "武器", rarity: 4),
            record(id: "4", day: 4, banner: .standard, name: "飞天御剑", itemType: "武器", rarity: 3)
        ]
        let plans = [
            CultivationPlan(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                targetName: "神里绫华",
                targetKind: "角色",
                currentLevel: 1,
                targetLevel: 90,
                requirements: [MaterialRequirement(id: "sakura", materialName: "绯樱绣球", required: 168, owned: 12)]
            ),
            CultivationPlan(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                targetName: "雷电将军",
                targetKind: "角色",
                currentLevel: 1,
                targetLevel: 90,
                requirements: [MaterialRequirement(id: "guard", materialName: "名刀镡", required: 129, owned: 42)]
            )
        ]

        let snapshot = WidgetSnapshot.make(
            accountStatus: account,
            gachaRecords: records,
            gachaSummary: GachaSummary.make(from: records),
            plans: plans,
            generatedAt: date(day: 25)
        )

        XCTAssertEqual(snapshot.signIn.statusText, "待签到")
        XCTAssertEqual(snapshot.signIn.actionTitle, "去签到")
        XCTAssertEqual(snapshot.signIn.nickname, "旅行者")
        XCTAssertEqual(snapshot.signIn.uid, "100000001")
        XCTAssertEqual(snapshot.gacha.totalPulls, 4)
        XCTAssertEqual(snapshot.gacha.fiveStarCount, 1)
        XCTAssertEqual(snapshot.gacha.fourStarCount, 1)
        XCTAssertEqual(snapshot.gacha.pitySinceLastFiveStar, 2)
        XCTAssertEqual(snapshot.gacha.lastFiveStarName, "神里绫华")
        XCTAssertEqual(snapshot.gacha.lastFiveStarDate, date(day: 2))
        XCTAssertEqual(snapshot.gacha.characterPulls, 2)
        XCTAssertEqual(snapshot.gacha.weaponPulls, 1)
        XCTAssertEqual(snapshot.gacha.standardPulls, 1)
        XCTAssertEqual(snapshot.planner.rows.map(\.targetName), ["神里绫华", "雷电将军"])
        XCTAssertEqual(snapshot.planner.rows.first?.materialName, "绯樱绣球")
        XCTAssertEqual(snapshot.planner.rows.first?.owned, 12)
        XCTAssertEqual(snapshot.planner.rows.first?.required, 168)
        XCTAssertEqual(snapshot.planner.rows.first?.completion ?? 0, 12.0 / 168.0, accuracy: 0.0001)
    }

    func testSnapshotUsesEmptyStatesWhenDataIsMissing() {
        let snapshot = WidgetSnapshot.make(
            accountStatus: .signedOut,
            gachaRecords: [],
            gachaSummary: GachaSummary.make(from: []),
            plans: [],
            generatedAt: date(day: 25)
        )

        XCTAssertEqual(snapshot.signIn.statusText, "未登录")
        XCTAssertEqual(snapshot.signIn.actionTitle, "去登录")
        XCTAssertEqual(snapshot.gacha.lastFiveStarName, "暂无五星记录")
        XCTAssertEqual(snapshot.gacha.pitySinceLastFiveStar, 0)
        XCTAssertTrue(snapshot.planner.rows.isEmpty)
    }

    func testSnapshotCountsCharacterEventTwoWithCharacterPullsWithoutMislabelingChronicledAsStandard() {
        let records = [
            record(id: "400-1", day: 1, banner: .characterEvent2, name: "浪涌之瞬", itemType: "角色", rarity: 5),
            record(id: "500-1", day: 2, banner: .chronicled, name: "晨风之诗", itemType: "角色", rarity: 4)
        ]

        let snapshot = WidgetSnapshot.make(
            accountStatus: .signedOut,
            gachaRecords: records,
            gachaSummary: GachaSummary.make(from: records),
            plans: [],
            generatedAt: date(day: 25)
        )

        XCTAssertEqual(snapshot.gacha.totalPulls, 2)
        XCTAssertEqual(snapshot.gacha.characterPulls, 1)
        XCTAssertEqual(snapshot.gacha.weaponPulls, 0)
        XCTAssertEqual(snapshot.gacha.standardPulls, 0)
    }

    private func record(id: String, day: Int, banner: BannerKind, name: String, itemType: String, rarity: Int) -> GachaRecord {
        GachaRecord(id: id, time: Self.date(day: day), banner: banner, name: name, itemType: itemType, rarity: rarity)
    }

    private static func date(day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        components.year = 2026
        components.month = 6
        components.day = day
        components.hour = 12
        return components.date!
    }

    private func date(day: Int) -> Date {
        Self.date(day: day)
    }
}
