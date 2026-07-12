import XCTest
@testable import PaimonToolbox

final class CultivationCalculatorTests: XCTestCase {
    func testWeaponRequirementsUseOnlyAscensionsCrossedByLevelRange() {
        let stages = [
            WeaponAscensionStage(breakpoint: 20, costs: [.init(materialName: "材料 A", count: 5)]),
            WeaponAscensionStage(breakpoint: 40, costs: [.init(materialName: "材料 A", count: 5), .init(materialName: "材料 B", count: 3)]),
            WeaponAscensionStage(breakpoint: 50, costs: [.init(materialName: "材料 B", count: 9)]),
            WeaponAscensionStage(breakpoint: 60, costs: [.init(materialName: "材料 C", count: 5)]),
            WeaponAscensionStage(breakpoint: 70, costs: [.init(materialName: "材料 C", count: 9)]),
            WeaponAscensionStage(breakpoint: 80, costs: [.init(materialName: "材料 D", count: 6)])
        ]

        let result = CultivationCalculator.weaponRequirements(
            stages: stages,
            levelRange: .init(current: 20, target: 60)
        )

        guard case .exact(let totals) = result else {
            return XCTFail("Expected exact weapon requirements")
        }
        XCTAssertEqual(totals, ["材料 A": 10, "材料 B": 12])
    }

    func testWeaponRequirementsReturnUnavailableForIncompleteStageData() {
        let result = CultivationCalculator.weaponRequirements(
            stages: [WeaponAscensionStage(breakpoint: 20, costs: [.init(materialName: "材料 A", count: 5)])],
            levelRange: .init(current: 1, target: 90)
        )

        XCTAssertEqual(result, .unavailable)
    }

    func testWeaponRequirementsReturnEmptyExactResultForReverseRange() {
        let stages = [20, 40, 50, 60, 70, 80].map {
            WeaponAscensionStage(breakpoint: $0, costs: [.init(materialName: "材料", count: 1)])
        }

        XCTAssertEqual(
            CultivationCalculator.weaponRequirements(stages: stages, levelRange: .init(current: 80, target: 20)),
            .exact([:])
        )
    }

    func testCharacterAscensionCalculatesExactTieredMaterialsForLevelOneToNinety() {
        let materials = CharacterCultivationMaterials(
            ascensionGemNames: ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"],
            bossMaterialName: "恒常机关之心",
            localSpecialtyName: "绯樱绣球",
            commonMaterialNames: ["破旧的刀镡", "影打刀镡", "名刀镡"],
            talentBookNames: ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"],
            weeklyBossMaterialName: "血玉之枝"
        )

        let requirements = CultivationCalculator.characterRequirements(
            materials: materials,
            levelRange: .init(current: 1, target: 90),
            normalAttackRange: .init(current: 1, target: 1),
            elementalSkillRange: .init(current: 1, target: 1),
            elementalBurstRange: .init(current: 1, target: 1)
        )

        XCTAssertEqual(requirements["哀叙冰玉碎屑"], 1)
        XCTAssertEqual(requirements["哀叙冰玉断片"], 9)
        XCTAssertEqual(requirements["哀叙冰玉块"], 9)
        XCTAssertEqual(requirements["哀叙冰玉"], 6)
        XCTAssertEqual(requirements["恒常机关之心"], 46)
        XCTAssertEqual(requirements["绯樱绣球"], 168)
        XCTAssertEqual(requirements["破旧的刀镡"], 18)
        XCTAssertEqual(requirements["影打刀镡"], 30)
        XCTAssertEqual(requirements["名刀镡"], 36)
        XCTAssertEqual(requirements["摩拉"], 2_092_530)
        XCTAssertEqual(requirements["大英雄的经验"], 419)
    }

    func testTalentCalculationForOneTalentLevelOneToTen() {
        let materials = CharacterCultivationMaterials(
            ascensionGemNames: ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"],
            bossMaterialName: "恒常机关之心",
            localSpecialtyName: "绯樱绣球",
            commonMaterialNames: ["破旧的刀镡", "影打刀镡", "名刀镡"],
            talentBookNames: ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"],
            weeklyBossMaterialName: "血玉之枝"
        )

        let requirements = CultivationCalculator.characterRequirements(
            materials: materials,
            levelRange: .init(current: 1, target: 1),
            normalAttackRange: .init(current: 1, target: 10),
            elementalSkillRange: .init(current: 1, target: 1),
            elementalBurstRange: .init(current: 1, target: 1)
        )

        XCTAssertEqual(requirements["「风雅」的教导"], 3)
        XCTAssertEqual(requirements["「风雅」的指引"], 21)
        XCTAssertEqual(requirements["「风雅」的哲学"], 38)
        XCTAssertEqual(requirements["破旧的刀镡"], 6)
        XCTAssertEqual(requirements["影打刀镡"], 22)
        XCTAssertEqual(requirements["名刀镡"], 31)
        XCTAssertEqual(requirements["血玉之枝"], 6)
        XCTAssertEqual(requirements["智识之冕"], 1)
        XCTAssertEqual(requirements["摩拉"], 1_652_500)
    }

    func testPlannerStatisticsAggregatesRequirementsAcrossPlans() {
        let plans = [
            CultivationPlan(
                id: UUID(),
                targetName: "神里绫华",
                targetKind: "角色",
                currentLevel: 1,
                targetLevel: 90,
                requirements: [
                    MaterialRequirement(id: "绯樱绣球", materialName: "绯樱绣球", required: 168, owned: 20),
                    MaterialRequirement(id: "摩拉", materialName: "摩拉", required: 420_000, owned: 10_000)
                ]
            ),
            CultivationPlan(
                id: UUID(),
                targetName: "胡桃",
                targetKind: "角色",
                currentLevel: 1,
                targetLevel: 80,
                requirements: [
                    MaterialRequirement(id: "霓裳花", materialName: "霓裳花", required: 108, owned: 0),
                    MaterialRequirement(id: "摩拉", materialName: "摩拉", required: 260_000, owned: 30_000)
                ]
            )
        ]

        let statistics = CultivationStatistics.aggregate(plans: plans, targetKind: "角色")

        XCTAssertEqual(statistics.first?.materialName, "摩拉")
        XCTAssertEqual(statistics.first?.required, 680_000)
        XCTAssertEqual(statistics.first?.owned, 40_000)
        XCTAssertEqual(statistics.first?.remaining, 640_000)
        XCTAssertEqual(statistics.map(\.materialName), ["摩拉", "绯樱绣球", "霓裳花"])
    }

    func testBossFightEstimatesUseRemainingBossMaterialShortfall() {
        let characters = [
            GameCharacter(
                id: 2,
                name: "神里绫华",
                element: "冰",
                weaponType: "单手剑",
                rarity: 5,
                region: "稻妻",
                materials: [],
                cultivation: CharacterCultivationMaterials(
                    ascensionGemNames: ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"],
                    bossMaterialName: "恒常机关之心",
                    localSpecialtyName: "绯樱绣球",
                    commonMaterialNames: ["破旧的刀镡", "影打刀镡", "名刀镡"],
                    talentBookNames: ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"],
                    weeklyBossMaterialName: "血玉之枝"
                )
            ),
            GameCharacter(
                id: 46,
                name: "胡桃",
                element: "火",
                weaponType: "长柄武器",
                rarity: 5,
                region: "璃月",
                materials: [],
                cultivation: CharacterCultivationMaterials(
                    ascensionGemNames: ["燃愿玛瑙碎屑", "燃愿玛瑙断片", "燃愿玛瑙块", "燃愿玛瑙"],
                    bossMaterialName: "未熟之玉",
                    localSpecialtyName: "霓裳花",
                    commonMaterialNames: ["骗骗花蜜", "微光花蜜", "原素花蜜"],
                    talentBookNames: ["「勤劳」的教导", "「勤劳」的指引", "「勤劳」的哲学"],
                    weeklyBossMaterialName: "魔王之刃·残片"
                )
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
                    MaterialRequirement(id: "恒常机关之心", materialName: "恒常机关之心", required: 46, owned: 1)
                ]
            ),
            CultivationPlan(
                id: UUID(),
                targetName: "胡桃",
                targetKind: "角色",
                currentLevel: 40,
                targetLevel: 80,
                requirements: [
                    MaterialRequirement(id: "未熟之玉", materialName: "未熟之玉", required: 26, owned: 0)
                ]
            )
        ]

        let estimates = CultivationStatistics.bossFightEstimates(plans: plans, characters: characters)

        XCTAssertEqual(estimates.map(\.bossMaterialName), ["恒常机关之心", "未熟之玉"])
        XCTAssertEqual(estimates.map(\.remainingMaterialCount), [45, 26])
        XCTAssertEqual(estimates.map(\.estimatedFightCount), [23, 13])
    }
}
