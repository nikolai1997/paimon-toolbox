import XCTest
@testable import PaimonToolbox

final class PlannerProgressTests: XCTestCase {
    func testCompletionAveragesMaterialProgressInsteadOfLettingMoraDominate() {
        let plan = CultivationPlan(
            id: UUID(),
            targetName: "妮可",
            targetKind: "角色",
            currentLevel: 1,
            targetLevel: 90,
            requirements: [
                MaterialRequirement(id: "mora", materialName: "摩拉", required: 7_050_030, owned: 7_050_030),
                MaterialRequirement(id: "crown", materialName: "智识之冕", required: 1, owned: 0)
            ]
        )

        XCTAssertEqual(plan.completion, 0.5, accuracy: 0.0001)
        XCTAssertEqual(AppFormatters.percentString(plan.completion), "50%")
    }

    func testCompletionDropsBelowOneHundredWhenCompletedMaterialIsUnchecked() {
        let plan = CultivationPlan(
            id: UUID(),
            targetName: "妮可",
            targetKind: "角色",
            currentLevel: 1,
            targetLevel: 90,
            requirements: [
                MaterialRequirement(id: "mora", materialName: "摩拉", required: 7_050_030, owned: 7_050_029),
                MaterialRequirement(id: "book", materialName: "大英雄的经验", required: 419, owned: 419)
            ]
        )

        XCTAssertLessThan(plan.completion, 1)
        XCTAssertNotEqual(AppFormatters.percentString(plan.completion), "100%")
    }
}
