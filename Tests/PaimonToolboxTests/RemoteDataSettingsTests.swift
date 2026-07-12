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

    func testFutureRefreshTimestampsAreClearedAndDoNotBlockUpdates() throws {
        let suiteName = "RemoteDataSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 100)
        defaults.set(now.addingTimeInterval(7 * 24 * 60 * 60), forKey: RemoteDataSettings.lastAutoRefreshSuccessKey)
        defaults.set(now.addingTimeInterval(7 * 24 * 60 * 60), forKey: RemoteDataSettings.lastAutoRefreshFailureKey)

        XCTAssertTrue(RemoteDataSettings.shouldAttemptAutoRefresh(now: now, userDefaults: defaults))
        XCTAssertNil(defaults.object(forKey: RemoteDataSettings.lastAutoRefreshSuccessKey))
        XCTAssertNil(defaults.object(forKey: RemoteDataSettings.lastAutoRefreshFailureKey))
    }
}
