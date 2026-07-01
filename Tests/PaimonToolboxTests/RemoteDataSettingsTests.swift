import XCTest
@testable import PaimonToolbox

final class RemoteDataSettingsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: RemoteDataSettings.githubMetadataURLKey)
        super.tearDown()
    }

    func testGitHubMetadataURLAlwaysUsesBundledEndpoint() {
        UserDefaults.standard.set("https://example.com/custom-metadata.json", forKey: RemoteDataSettings.githubMetadataURLKey)

        XCTAssertEqual(RemoteDataSettings.githubMetadataURLString, RemoteDataSettings.defaultGitHubMetadataURLString)
    }
}
