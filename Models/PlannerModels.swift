import Foundation

struct MaterialRequirement: Codable, Identifiable, Equatable {
    var id: String
    var materialName: String
    var required: Int
    var owned: Int

    var remaining: Int {
        max(required - owned, 0)
    }
}

struct CultivationPlan: Codable, Identifiable, Equatable {
    var id: UUID
    var targetName: String
    var targetKind: String
    var targetIconURL: URL? = nil
    var currentLevel: Int
    var targetLevel: Int
    var normalAttackCurrentLevel: Int? = nil
    var normalAttackTargetLevel: Int? = nil
    var elementalSkillCurrentLevel: Int? = nil
    var elementalSkillTargetLevel: Int? = nil
    var elementalBurstCurrentLevel: Int? = nil
    var elementalBurstTargetLevel: Int? = nil
    var requirements: [MaterialRequirement]

    var completion: Double {
        guard !requirements.isEmpty else { return 1 }
        let progress = requirements.reduce(0.0) { partialResult, requirement in
            guard requirement.required > 0 else { return partialResult + 1 }
            let owned = min(max(requirement.owned, 0), requirement.required)
            return partialResult + (Double(owned) / Double(requirement.required))
        }
        return progress / Double(requirements.count)
    }
}
