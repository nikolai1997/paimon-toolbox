import XCTest
@testable import PaimonToolbox

@MainActor
final class PlannerServiceTests: XCTestCase {
    func testNewPlannerStoreStartsEmptyInsteadOfSamplePlan() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = LocalPlannerService(plansURL: directory.appending(path: "plans.json"))

        let plans = try await service.loadPlans()

        XCTAssertEqual(plans, [])
    }

    func testPlannerStoreMigratesPlansFromLegacyLocationWhenPrimaryIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appending(path: "plans.json")
        let legacyURL = directory.appending(path: "legacy-plans.json")
        let saved = [
            CultivationPlan(
                id: UUID(),
                targetName: "神里绫华",
                targetKind: "角色",
                targetIconURL: nil,
                currentLevel: 1,
                targetLevel: 90,
                normalAttackCurrentLevel: 1,
                normalAttackTargetLevel: 1,
                elementalSkillCurrentLevel: 1,
                elementalSkillTargetLevel: 1,
                elementalBurstCurrentLevel: 1,
                elementalBurstTargetLevel: 1,
                requirements: []
            )
        ]
        let data = try JSONEncoder().encode(saved)
        try data.write(to: legacyURL, options: .atomic)
        let service = LocalPlannerService(plansURL: primaryURL, legacyPlanURLs: [legacyURL])

        let loaded = try await service.loadPlans()

        XCTAssertEqual(loaded, saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primaryURL.path()))
    }

    func testAppStoreCreatesCharacterPlanFromMetadataMaterials() async {
        let plannerService = InMemoryPlannerService()
        let store = AppStore(plannerService: plannerService)
        let character = GameCharacter(
            id: 10000002,
            name: "神里绫华",
            element: "冰",
            weaponType: "单手剑",
            rarity: 5,
            region: "稻妻",
            iconURL: URL(string: "https://static.example.com/avatar/10000002.png"),
            materials: ["绯樱绣球", "恒常机关之心"]
        )

        await store.createCharacterPlan(for: character)

        XCTAssertEqual(store.plans.count, 1)
        XCTAssertEqual(store.plans.first?.targetName, "神里绫华")
        XCTAssertEqual(store.plans.first?.targetKind, "角色")
        XCTAssertEqual(store.plans.first?.targetIconURL?.absoluteString, "https://static.example.com/avatar/10000002.png")
        XCTAssertEqual(store.plans.first?.requirements.map(\.materialName), ["绯樱绣球", "恒常机关之心"])
        XCTAssertEqual(plannerService.savedPlans.count, 1)
    }

    func testAppStoreCreatesCharacterPlanWithExactCultivationTables() async throws {
        let plannerService = InMemoryPlannerService()
        let store = AppStore(plannerService: plannerService)
        let character = GameCharacter(
            id: 10000002,
            name: "神里绫华",
            element: "冰",
            weaponType: "单手剑",
            rarity: 5,
            region: "稻妻",
            iconURL: URL(string: "https://static.example.com/avatar/10000002.png"),
            materials: ["哀叙冰玉", "恒常机关之心", "绯樱绣球", "名刀镡", "「风雅」的哲学", "血玉之枝"],
            cultivation: CharacterCultivationMaterials(
                ascensionGemNames: ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"],
                bossMaterialName: "恒常机关之心",
                localSpecialtyName: "绯樱绣球",
                commonMaterialNames: ["破旧的刀镡", "影打刀镡", "名刀镡"],
                talentBookNames: ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"],
                weeklyBossMaterialName: "血玉之枝"
            )
        )

        await store.createCharacterPlan(
            for: character,
            currentLevel: 1,
            targetLevel: 90,
            normalAttackCurrentLevel: 1,
            normalAttackTargetLevel: 10,
            elementalSkillCurrentLevel: 1,
            elementalSkillTargetLevel: 1,
            elementalBurstCurrentLevel: 1,
            elementalBurstTargetLevel: 1
        )

        let plan = try XCTUnwrap(store.plans.first)
        XCTAssertEqual(plan.currentLevel, 1)
        XCTAssertEqual(plan.targetLevel, 90)
        XCTAssertEqual(plan.normalAttackTargetLevel, 10)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "哀叙冰玉碎屑" }?.required, 1)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "绯樱绣球" }?.required, 168)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "大英雄的经验" }?.required, 419)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "「风雅」的哲学" }?.required, 38)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "智识之冕" }?.required, 1)
        XCTAssertEqual(plannerService.savedPlans.count, 1)
    }

    func testAppStoreCreatesWeaponPlanFromExactAscensionStages() async throws {
        let plannerService = InMemoryPlannerService()
        let store = AppStore(plannerService: plannerService)
        let weapon = Weapon(
            id: 11509,
            name: "雾切之回光",
            type: "单手剑",
            rarity: 5,
            stat: "暴击伤害",
            materials: ["远海夷地的瑚枝"],
            ascensionStages: [
                .init(breakpoint: 20, costs: [.init(materialName: "远海夷地的瑚枝", count: 5)]),
                .init(breakpoint: 40, costs: [.init(materialName: "远海夷地的玉枝", count: 5)]),
                .init(breakpoint: 50, costs: [.init(materialName: "远海夷地的玉枝", count: 9)]),
                .init(breakpoint: 60, costs: [.init(materialName: "远海夷地的琼枝", count: 5)]),
                .init(breakpoint: 70, costs: [.init(materialName: "远海夷地的琼枝", count: 9)]),
                .init(breakpoint: 80, costs: [.init(materialName: "远海夷地的金枝", count: 6)])
            ]
        )

        await store.createWeaponPlan(for: weapon, currentLevel: 20, targetLevel: 60)

        let plan = try XCTUnwrap(store.plans.first)
        XCTAssertEqual(plan.currentLevel, 20)
        XCTAssertEqual(plan.targetLevel, 60)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "远海夷地的瑚枝" }?.required, 5)
        XCTAssertEqual(plan.requirements.first { $0.materialName == "远海夷地的玉枝" }?.required, 14)
    }

    func testAppStoreDoesNotCreateWeaponPlanWhenExactStagesAreMissing() async {
        let plannerService = InMemoryPlannerService()
        let store = AppStore(plannerService: plannerService)
        let weapon = Weapon(
            id: 1,
            name: "缺少数据的武器",
            type: "单手剑",
            rarity: 5,
            stat: "攻击力",
            materials: ["材料"]
        )

        await store.createWeaponPlan(for: weapon)

        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertTrue(plannerService.savedPlans.isEmpty)
        XCTAssertEqual(store.errorMessage, "当前资料缺少完整武器突破数量，暂时无法创建精确计划")
    }

    func testPlannerMutationsRollBackWhenPersistenceFails() async {
        let original = CultivationPlan(
            id: UUID(),
            targetName: "原计划",
            targetKind: "角色",
            currentLevel: 1,
            targetLevel: 90,
            requirements: [MaterialRequirement(id: "材料", materialName: "材料", required: 10, owned: 1)]
        )
        let store = AppStore(plannerService: FailingPlannerService())
        store.plans = [original]

        await store.deletePlan(id: original.id)
        XCTAssertEqual(store.plans, [original])

        await store.updateRequirement(planID: original.id, requirementID: "材料", owned: 9)
        XCTAssertEqual(store.plans, [original])

        let character = GameCharacter(
            id: 1,
            name: "新角色",
            element: "冰",
            weaponType: "单手剑",
            rarity: 5,
            region: "蒙德",
            materials: ["材料"]
        )
        await store.createCharacterPlan(for: character)
        XCTAssertEqual(store.plans, [original])
        XCTAssertTrue(store.errorMessage?.contains("保存养成计划失败") == true)
    }
}

@MainActor
private final class InMemoryPlannerService: PlannerServicing {
    var savedPlans: [CultivationPlan] = []

    func loadPlans() async throws -> [CultivationPlan] {
        savedPlans
    }

    func savePlans(_ plans: [CultivationPlan]) async throws {
        savedPlans = plans
    }
}

@MainActor
private final class FailingPlannerService: PlannerServicing {
    func loadPlans() async throws -> [CultivationPlan] { [] }

    func savePlans(_ plans: [CultivationPlan]) async throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
