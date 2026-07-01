import Foundation

enum PlannerTargetSearch {
    static func filteredCharacters(_ characters: [GameCharacter], query: String) -> [GameCharacter] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return characters
        }
        return characters.filter { character in
            character.name.localizedStandardContains(normalizedQuery)
                || character.element.localizedStandardContains(normalizedQuery)
                || character.weaponType.localizedStandardContains(normalizedQuery)
                || character.region.localizedStandardContains(normalizedQuery)
        }
    }

    static func filteredWeapons(_ weapons: [Weapon], query: String) -> [Weapon] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return weapons
        }
        return weapons.filter { weapon in
            weapon.name.localizedStandardContains(normalizedQuery)
                || weapon.type.localizedStandardContains(normalizedQuery)
                || weapon.stat.localizedStandardContains(normalizedQuery)
        }
    }
}
