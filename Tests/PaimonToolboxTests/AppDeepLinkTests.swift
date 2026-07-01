import XCTest
@testable import PaimonToolbox

final class AppDeepLinkTests: XCTestCase {
    func testParsesWidgetDestinations() {
        XCTAssertEqual(AppDeepLink(url: URL(string: "paimontoolbox://account/signin")!), .accountSignIn)
        XCTAssertEqual(AppDeepLink(url: URL(string: "paimontoolbox://gacha")!), .gacha)
        XCTAssertEqual(AppDeepLink(url: URL(string: "paimontoolbox://planner")!), .planner)
        XCTAssertEqual(AppDeepLink(url: URL(string: "paimontoolbox://overview")!), .overview)
        XCTAssertEqual(AppDeepLink(url: URL(string: "paimontoolbox://widget/refresh")!), .widgetRefresh)
    }

    func testRejectsUnknownSchemesAndPaths() {
        XCTAssertNil(AppDeepLink(url: URL(string: "https://example.com/gacha")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "paimontoolbox://unknown")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "paimontoolbox://gacha/extra")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "paimontoolbox://account/logout")!))
        XCTAssertNil(AppDeepLink(url: URL(string: "paimontoolbox://widget/unknown")!))
    }
}
