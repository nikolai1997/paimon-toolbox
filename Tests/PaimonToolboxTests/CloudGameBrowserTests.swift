import XCTest
@testable import PaimonToolbox

@MainActor
final class CloudGameBrowserTests: XCTestCase {
    func testAccountChangeAndSignOutClearCloudSession() async throws {
        let browser = CloudGameBrowser()
        await browser.open(session: MapWebSessionContext(accountID: "account-a", cookies: []))
        let original = try XCTUnwrap(browser.webView)
        browser.invalidateSession(ifAccountChangedTo: "account-a")
        XCTAssertTrue(browser.webView === original)
        browser.invalidateSession(ifAccountChangedTo: "account-b")
        XCTAssertNil(browser.webView)
        await browser.open(session: MapWebSessionContext(accountID: "account-b", cookies: []))
        browser.invalidateSession(ifAccountChangedTo: nil)
        XCTAssertNil(browser.webView)
        XCTAssertFalse(browser.isLoading)
    }

    func testOpeningAgainKeepsPageAndClosingCreatesNewSession() async throws {
        let browser = CloudGameBrowser()
        await browser.open(session: .guest)
        let original = try XCTUnwrap(browser.webView)
        XCTAssertFalse(original.configuration.websiteDataStore.isPersistent)

        await browser.open(session: .guest)
        XCTAssertTrue(browser.webView === original)

        browser.close()
        XCTAssertNil(browser.webView)
        XCTAssertFalse(browser.isLoading)

        await browser.open(session: .guest)
        XCTAssertNotNil(browser.webView)
        XCTAssertFalse(browser.webView === original)
        browser.close()
    }
}
