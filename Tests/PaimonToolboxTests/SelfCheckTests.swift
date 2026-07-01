import XCTest
@testable import PaimonToolbox

final class SelfCheckTests: XCTestCase {
    func testSupportsCurrentMetadataVersionPrefixes() {
        XCTAssertTrue(SelfCheck.supportsMetadataVersion("snap-2026.06.29"))
        XCTAssertTrue(SelfCheck.supportsMetadataVersion("genshin-db-2026.06.29"))
        XCTAssertFalse(SelfCheck.supportsMetadataVersion("fixture-2026.06.29"))
    }

    func testBundledMetadataMatchesSelfCheckVolumeExpectations() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "metadata.sample", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: data)

        XCTAssertTrue(SelfCheck.supportsMetadataVersion(bundle.version))
        XCTAssertGreaterThan(bundle.characters.count, 100)
        XCTAssertGreaterThan(bundle.weapons.count, 200)
        XCTAssertGreaterThan(bundle.materials.count, 800)
    }
}
