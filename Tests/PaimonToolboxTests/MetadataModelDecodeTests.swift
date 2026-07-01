import XCTest
@testable import PaimonToolbox

final class MetadataModelDecodeTests: XCTestCase {
    func testMaterialCategoryDecodesNumericValuesAsString() throws {
        let json = """
        {
          "version": "numeric-category-test",
          "updatedAt": "2026-06-24T00:00:00Z",
          "characters": [],
          "weapons": [],
          "materials": [
            {
              "id": 104001,
              "name": "大英雄的经验",
              "category": 2,
              "source": "活动奖励"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: json)

        XCTAssertEqual(bundle.materials.first?.category, "2")
    }

    func testCharacterCultivationMaterialsDecodeWhenPresent() throws {
        let json = """
        {
          "version": "cultivation-test",
          "updatedAt": "2026-06-24T00:00:00Z",
          "characters": [
            {
              "id": 10000002,
              "name": "神里绫华",
              "element": "冰",
              "weaponType": "单手剑",
              "rarity": 5,
              "region": "稻妻",
              "materials": ["哀叙冰玉"],
              "cultivation": {
                "ascensionGemNames": ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"],
                "bossMaterialName": "恒常机关之心",
                "localSpecialtyName": "绯樱绣球",
                "commonMaterialNames": ["破旧的刀镡", "影打刀镡", "名刀镡"],
                "talentBookNames": ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"],
                "weeklyBossMaterialName": "血玉之枝"
              }
            }
          ],
          "weapons": [],
          "materials": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: json)

        XCTAssertEqual(bundle.characters.first?.cultivation?.talentBookNames.last, "「风雅」的哲学")
        XCTAssertEqual(bundle.characters.first?.cultivation?.hasExactMaterialTiers, true)
    }
}
