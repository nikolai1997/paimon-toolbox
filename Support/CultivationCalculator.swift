import Foundation

struct CultivationLevelRange: Equatable {
    var current: Int
    var target: Int

    var normalized: CultivationLevelRange {
        CultivationLevelRange(
            current: max(current, 1),
            target: max(target, max(current, 1))
        )
    }
}

struct CultivationMaterialStatistic: Identifiable, Equatable {
    var id: String { materialName }
    var materialName: String
    var required: Int
    var owned: Int

    var remaining: Int {
        max(required - owned, 0)
    }
}

struct CultivationBossFightEstimate: Identifiable, Equatable {
    var id: String { bossMaterialName }
    var bossMaterialName: String
    var remainingMaterialCount: Int
    var estimatedFightCount: Int
    var materialDropsPerFight: Int
}

enum CultivationCalculator {
    static let moraName = "摩拉"
    static let heroExperienceName = "大英雄的经验"
    static let crownName = "智识之冕"

    static func characterRequirements(
        materials: CharacterCultivationMaterials,
        levelRange: CultivationLevelRange,
        normalAttackRange: CultivationLevelRange,
        elementalSkillRange: CultivationLevelRange,
        elementalBurstRange: CultivationLevelRange
    ) -> [String: Int] {
        var totals: [String: Int] = [:]
        addCharacterLevelRequirements(to: &totals, materials: materials, range: levelRange)
        addTalentRequirements(to: &totals, materials: materials, range: normalAttackRange)
        addTalentRequirements(to: &totals, materials: materials, range: elementalSkillRange)
        addTalentRequirements(to: &totals, materials: materials, range: elementalBurstRange)
        return totals
    }

    static func materialRequirements(from totals: [String: Int]) -> [MaterialRequirement] {
        totals
            .filter { !$0.key.isEmpty && $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.key == moraName { return true }
                if rhs.key == moraName { return false }
                if lhs.key == heroExperienceName { return true }
                if rhs.key == heroExperienceName { return false }
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            .map { name, required in
                MaterialRequirement(id: name, materialName: name, required: required, owned: 0)
            }
    }

    private static func addCharacterLevelRequirements(
        to totals: inout [String: Int],
        materials: CharacterCultivationMaterials,
        range: CultivationLevelRange
    ) {
        let range = range.normalized
        guard range.current < range.target else { return }

        for step in ascensionSteps where crosses(level: step.breakpoint, range: range) {
            add(materials.ascensionGemNames, at: 0, count: step.gemSliver, to: &totals)
            add(materials.ascensionGemNames, at: 1, count: step.gemFragment, to: &totals)
            add(materials.ascensionGemNames, at: 2, count: step.gemChunk, to: &totals)
            add(materials.ascensionGemNames, at: 3, count: step.gemGemstone, to: &totals)
            add(materials.bossMaterialName, step.bossMaterial, to: &totals)
            add(materials.localSpecialtyName, step.localSpecialty, to: &totals)
            add(materials.commonMaterialNames, at: 0, count: step.commonLow, to: &totals)
            add(materials.commonMaterialNames, at: 1, count: step.commonMid, to: &totals)
            add(materials.commonMaterialNames, at: 2, count: step.commonHigh, to: &totals)
            add(moraName, step.mora, to: &totals)
        }

        let experience = avatarExperience(from: range.current, to: range.target)
        add(heroExperienceName, Int(ceil(Double(experience) / 20_000.0)), to: &totals)
        add(moraName, experience / 5, to: &totals)
    }

    private static func addTalentRequirements(
        to totals: inout [String: Int],
        materials: CharacterCultivationMaterials,
        range: CultivationLevelRange
    ) {
        let range = range.normalized
        guard range.current < range.target else { return }

        for step in talentSteps where range.current < step.targetLevel && range.target >= step.targetLevel {
            add(materials.talentBookNames, at: 0, count: step.bookLow, to: &totals)
            add(materials.talentBookNames, at: 1, count: step.bookMid, to: &totals)
            add(materials.talentBookNames, at: 2, count: step.bookHigh, to: &totals)
            add(materials.commonMaterialNames, at: 0, count: step.commonLow, to: &totals)
            add(materials.commonMaterialNames, at: 1, count: step.commonMid, to: &totals)
            add(materials.commonMaterialNames, at: 2, count: step.commonHigh, to: &totals)
            add(materials.weeklyBossMaterialName, step.weeklyBoss, to: &totals)
            add(crownName, step.crown, to: &totals)
            add(moraName, step.mora, to: &totals)
        }
    }

    private static func avatarExperience(from currentLevel: Int, to targetLevel: Int) -> Int {
        let currentLevel = min(max(currentLevel, 1), 90)
        let targetLevel = min(max(targetLevel, currentLevel), 90)
        guard currentLevel < targetLevel else { return 0 }
        return avatarLevelExperience[currentLevel..<targetLevel].reduce(0, +)
    }

    private static func crosses(level breakpoint: Int, range: CultivationLevelRange) -> Bool {
        range.current <= breakpoint && range.target > breakpoint
    }

    private static func add(_ name: String, _ count: Int, to totals: inout [String: Int]) {
        guard !name.isEmpty, count > 0 else { return }
        totals[name, default: 0] += count
    }

    private static func add(_ names: [String], at index: Int, count: Int, to totals: inout [String: Int]) {
        guard names.indices.contains(index) else { return }
        add(names[index], count, to: &totals)
    }

    private static let ascensionSteps: [CharacterAscensionStep] = [
        .init(breakpoint: 20, gemSliver: 1, gemFragment: 0, gemChunk: 0, gemGemstone: 0, bossMaterial: 0, localSpecialty: 3, commonLow: 3, commonMid: 0, commonHigh: 0, mora: 20_000),
        .init(breakpoint: 40, gemSliver: 0, gemFragment: 3, gemChunk: 0, gemGemstone: 0, bossMaterial: 2, localSpecialty: 10, commonLow: 15, commonMid: 0, commonHigh: 0, mora: 40_000),
        .init(breakpoint: 50, gemSliver: 0, gemFragment: 6, gemChunk: 0, gemGemstone: 0, bossMaterial: 4, localSpecialty: 20, commonLow: 0, commonMid: 12, commonHigh: 0, mora: 60_000),
        .init(breakpoint: 60, gemSliver: 0, gemFragment: 0, gemChunk: 3, gemGemstone: 0, bossMaterial: 8, localSpecialty: 30, commonLow: 0, commonMid: 18, commonHigh: 0, mora: 80_000),
        .init(breakpoint: 70, gemSliver: 0, gemFragment: 0, gemChunk: 6, gemGemstone: 0, bossMaterial: 12, localSpecialty: 45, commonLow: 0, commonMid: 0, commonHigh: 12, mora: 100_000),
        .init(breakpoint: 80, gemSliver: 0, gemFragment: 0, gemChunk: 0, gemGemstone: 6, bossMaterial: 20, localSpecialty: 60, commonLow: 0, commonMid: 0, commonHigh: 24, mora: 120_000)
    ]

    private static let talentSteps: [TalentLevelStep] = [
        .init(targetLevel: 2, bookLow: 3, bookMid: 0, bookHigh: 0, commonLow: 6, commonMid: 0, commonHigh: 0, weeklyBoss: 0, crown: 0, mora: 12_500),
        .init(targetLevel: 3, bookLow: 0, bookMid: 2, bookHigh: 0, commonLow: 0, commonMid: 3, commonHigh: 0, weeklyBoss: 0, crown: 0, mora: 17_500),
        .init(targetLevel: 4, bookLow: 0, bookMid: 4, bookHigh: 0, commonLow: 0, commonMid: 4, commonHigh: 0, weeklyBoss: 0, crown: 0, mora: 25_000),
        .init(targetLevel: 5, bookLow: 0, bookMid: 6, bookHigh: 0, commonLow: 0, commonMid: 6, commonHigh: 0, weeklyBoss: 0, crown: 0, mora: 30_000),
        .init(targetLevel: 6, bookLow: 0, bookMid: 9, bookHigh: 0, commonLow: 0, commonMid: 9, commonHigh: 0, weeklyBoss: 0, crown: 0, mora: 37_500),
        .init(targetLevel: 7, bookLow: 0, bookMid: 0, bookHigh: 4, commonLow: 0, commonMid: 0, commonHigh: 4, weeklyBoss: 1, crown: 0, mora: 120_000),
        .init(targetLevel: 8, bookLow: 0, bookMid: 0, bookHigh: 6, commonLow: 0, commonMid: 0, commonHigh: 6, weeklyBoss: 1, crown: 0, mora: 260_000),
        .init(targetLevel: 9, bookLow: 0, bookMid: 0, bookHigh: 12, commonLow: 0, commonMid: 0, commonHigh: 9, weeklyBoss: 2, crown: 0, mora: 450_000),
        .init(targetLevel: 10, bookLow: 0, bookMid: 0, bookHigh: 16, commonLow: 0, commonMid: 0, commonHigh: 12, weeklyBoss: 2, crown: 1, mora: 700_000)
    ]

    private static let avatarLevelExperience: [Int] = [
        0,
        1_000, 1_325, 1_700, 2_150, 2_625, 3_150, 3_725, 4_350, 5_000, 5_700,
        6_450, 7_225, 8_050, 8_925, 9_825, 10_750, 11_725, 12_725, 13_775, 14_875,
        16_800, 18_000, 19_250, 20_550, 21_875, 23_250, 24_650, 26_100, 27_575, 29_100,
        30_650, 32_250, 33_875, 35_550, 37_250, 38_975, 40_750, 42_575, 44_425, 46_300,
        50_625, 52_700, 54_775, 56_900, 59_075, 61_275, 63_525, 65_800, 68_125, 70_475,
        76_500, 79_050, 81_650, 84_275, 86_950, 89_650, 92_400, 95_175, 98_000, 100_875,
        108_950, 112_050, 115_175, 118_325, 121_525, 124_775, 128_075, 131_400, 134_775, 138_175,
        148_700, 152_375, 156_075, 159_825, 163_600, 167_425, 171_300, 175_225, 179_175, 183_175,
        216_225, 243_025, 273_100, 306_800, 344_600, 386_950, 434_425, 487_625, 547_200, 0
    ]
}

enum CultivationStatistics {
    static func aggregate(plans: [CultivationPlan], targetKind: String? = nil) -> [CultivationMaterialStatistic] {
        var totals: [String: (required: Int, owned: Int)] = [:]
        for plan in plans where targetKind == nil || plan.targetKind == targetKind {
            for requirement in plan.requirements {
                var value = totals[requirement.materialName, default: (required: 0, owned: 0)]
                value.required += requirement.required
                value.owned += requirement.owned
                totals[requirement.materialName] = value
            }
        }

        return totals
            .map { name, value in
                CultivationMaterialStatistic(materialName: name, required: value.required, owned: value.owned)
            }
            .sorted { lhs, rhs in
                if lhs.remaining != rhs.remaining {
                    return lhs.remaining > rhs.remaining
                }
                return lhs.materialName.localizedStandardCompare(rhs.materialName) == .orderedAscending
            }
    }

    static func bossFightEstimates(
        plans: [CultivationPlan],
        characters: [GameCharacter],
        materialDropsPerFight: Int = 2
    ) -> [CultivationBossFightEstimate] {
        guard materialDropsPerFight > 0 else { return [] }

        let characterByName = Dictionary(uniqueKeysWithValues: characters.map { ($0.name, $0) })
        var remainingByBossMaterial: [String: Int] = [:]

        for plan in plans where plan.targetKind == "角色" {
            guard let bossMaterialName = characterByName[plan.targetName]?.cultivation?.bossMaterialName,
                  !bossMaterialName.isEmpty,
                  let requirement = plan.requirements.first(where: { $0.materialName == bossMaterialName }) else {
                continue
            }
            remainingByBossMaterial[bossMaterialName, default: 0] += requirement.remaining
        }

        return remainingByBossMaterial
            .filter { $0.value > 0 }
            .map { bossMaterialName, remainingMaterialCount in
                CultivationBossFightEstimate(
                    bossMaterialName: bossMaterialName,
                    remainingMaterialCount: remainingMaterialCount,
                    estimatedFightCount: (remainingMaterialCount + materialDropsPerFight - 1) / materialDropsPerFight,
                    materialDropsPerFight: materialDropsPerFight
                )
            }
            .sorted { lhs, rhs in
                if lhs.estimatedFightCount != rhs.estimatedFightCount {
                    return lhs.estimatedFightCount > rhs.estimatedFightCount
                }
                return lhs.bossMaterialName.localizedStandardCompare(rhs.bossMaterialName) == .orderedAscending
            }
    }
}

private struct CharacterAscensionStep {
    var breakpoint: Int
    var gemSliver: Int
    var gemFragment: Int
    var gemChunk: Int
    var gemGemstone: Int
    var bossMaterial: Int
    var localSpecialty: Int
    var commonLow: Int
    var commonMid: Int
    var commonHigh: Int
    var mora: Int
}

private struct TalentLevelStep {
    var targetLevel: Int
    var bookLow: Int
    var bookMid: Int
    var bookHigh: Int
    var commonLow: Int
    var commonMid: Int
    var commonHigh: Int
    var weeklyBoss: Int
    var crown: Int
    var mora: Int
}
