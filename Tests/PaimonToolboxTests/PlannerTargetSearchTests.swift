import XCTest
@testable import PaimonToolbox

final class PlannerTargetSearchTests: XCTestCase {
    func testCharacterSearchMatchesNameElementWeaponAndRegion() {
        let characters = [
            GameCharacter(id: 1, name: "神里绫华", element: "冰", weaponType: "单手剑", rarity: 5, region: "稻妻", materials: []),
            GameCharacter(id: 2, name: "芙宁娜", element: "水", weaponType: "单手剑", rarity: 5, region: "枫丹", materials: []),
            GameCharacter(id: 3, name: "胡桃", element: "火", weaponType: "长柄武器", rarity: 5, region: "璃月", materials: [])
        ]

        XCTAssertEqual(PlannerTargetSearch.filteredCharacters(characters, query: "芙").map(\.name), ["芙宁娜"])
        XCTAssertEqual(PlannerTargetSearch.filteredCharacters(characters, query: "冰").map(\.name), ["神里绫华"])
        XCTAssertEqual(PlannerTargetSearch.filteredCharacters(characters, query: "长柄").map(\.name), ["胡桃"])
        XCTAssertEqual(PlannerTargetSearch.filteredCharacters(characters, query: "璃月").map(\.name), ["胡桃"])
    }

    func testWeaponSearchMatchesNameTypeAndStat() {
        let weapons = [
            Weapon(id: 1, name: "雾切之回光", type: "单手剑", rarity: 5, stat: "暴击伤害", materials: []),
            Weapon(id: 2, name: "护摩之杖", type: "长柄武器", rarity: 5, stat: "暴击伤害", materials: []),
            Weapon(id: 3, name: "祭礼弓", type: "弓", rarity: 4, stat: "元素充能效率", materials: [])
        ]

        XCTAssertEqual(PlannerTargetSearch.filteredWeapons(weapons, query: "护摩").map(\.name), ["护摩之杖"])
        XCTAssertEqual(PlannerTargetSearch.filteredWeapons(weapons, query: "弓").map(\.name), ["祭礼弓"])
        XCTAssertEqual(PlannerTargetSearch.filteredWeapons(weapons, query: "充能").map(\.name), ["祭礼弓"])
    }

    func testBlankSearchReturnsOriginalOrder() {
        let characters = [
            GameCharacter(id: 1, name: "神里绫华", element: "冰", weaponType: "单手剑", rarity: 5, region: "稻妻", materials: []),
            GameCharacter(id: 2, name: "芙宁娜", element: "水", weaponType: "单手剑", rarity: 5, region: "枫丹", materials: [])
        ]

        XCTAssertEqual(PlannerTargetSearch.filteredCharacters(characters, query: "  ").map(\.name), ["神里绫华", "芙宁娜"])
    }
}
