import XCTest
@testable import PaimonToolbox

final class MetadataArtworkSelectionTests: XCTestCase {
    func testCharacterInspectorUsesFrontIconBeforeSidePortrait() {
        let iconURL = URL(string: "https://static.example.com/avatar.png")
        let portraitURL = URL(string: "https://static.example.com/side.png")
        let character = GameCharacter(
            id: 1,
            name: "莉奈娅",
            element: "岩",
            weaponType: "法器",
            rarity: 5,
            region: "冒险家协会",
            iconURL: iconURL,
            portraitURL: portraitURL,
            materials: []
        )

        XCTAssertEqual(character.inspectorArtworkURL, iconURL)
    }

    func testCharacterInspectorFallsBackToPortraitWhenIconIsMissing() {
        let portraitURL = URL(string: "https://static.example.com/side.png")
        let character = GameCharacter(
            id: 1,
            name: "莉奈娅",
            element: "岩",
            weaponType: "法器",
            rarity: 5,
            region: "冒险家协会",
            iconURL: nil,
            portraitURL: portraitURL,
            materials: []
        )

        XCTAssertEqual(character.inspectorArtworkURL, portraitURL)
    }
}
