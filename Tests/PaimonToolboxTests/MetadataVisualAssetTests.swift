import XCTest
@testable import PaimonToolbox

final class MetadataVisualAssetTests: XCTestCase {
    func testBundledMetadataContainsVisualAssets() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "metadata.sample", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: data)

        XCTAssertGreaterThan(bundle.characters.count, 100)
        XCTAssertTrue(bundle.characters.allSatisfy { $0.iconURL != nil })
        XCTAssertTrue(bundle.characters.allSatisfy { $0.portraitURL != nil })
        XCTAssertTrue(bundle.weapons.allSatisfy { $0.iconURL != nil })
        XCTAssertTrue(bundle.materials.allSatisfy { $0.iconURL != nil })
    }

    func testCharacterWeaponAndMaterialDecodeVisualAssets() throws {
        let json = """
        {
          "version": "visual-test",
          "updatedAt": "2026-06-24T00:00:00Z",
          "characters": [
            {
              "id": 10000002,
              "name": "神里绫华",
              "element": "冰",
              "weaponType": "单手剑",
              "rarity": 5,
              "region": "稻妻",
              "iconURL": "https://static.example.com/avatar/10000002.png",
              "portraitURL": "https://static.example.com/portrait/10000002.png",
              "materials": ["绯樱绣球"]
            }
          ],
          "weapons": [
            {
              "id": 11502,
              "name": "雾切之回光",
              "type": "单手剑",
              "rarity": 5,
              "stat": "暴击伤害",
              "iconURL": "https://static.example.com/weapon/11502.png",
              "materials": ["远海夷地的金枝"]
            }
          ],
          "materials": [
            {
              "id": 101202,
              "name": "绯樱绣球",
              "category": "区域特产",
              "source": "稻妻野外采集",
              "iconURL": "https://static.example.com/material/101202.png"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: json)

        XCTAssertEqual(bundle.characters.first?.iconURL?.absoluteString, "https://static.example.com/avatar/10000002.png")
        XCTAssertEqual(bundle.characters.first?.portraitURL?.absoluteString, "https://static.example.com/portrait/10000002.png")
        XCTAssertEqual(bundle.weapons.first?.iconURL?.absoluteString, "https://static.example.com/weapon/11502.png")
        XCTAssertEqual(bundle.materials.first?.iconURL?.absoluteString, "https://static.example.com/material/101202.png")
    }

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
}
