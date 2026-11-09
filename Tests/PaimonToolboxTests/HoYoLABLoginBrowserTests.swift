import AppKit
import WebKit
import XCTest
@testable import PaimonToolbox

final class HoYoLABLoginBrowserTests: XCTestCase {
    @MainActor
    func testCrossLoginPopupCanNotifyOpenerAndCloseWithoutReplacingLoginPage() async throws {
        let browser = HoYoLABLoginBrowser(loginURL: URL(string: "about:blank")!)
        defer { browser.clear() }
        browser.webView.loadHTMLString("""
        <html><body id="login-fixture">Login page</body>
        <script>
        window.addEventListener('message', function(event) {
            window.loginMessage = event.data.type;
        });
        </script></html>
        """, baseURL: nil)
        try await waitUntil {
            (try? await browser.webView.evaluateJavaScript("document.body && document.body.id === 'login-fixture'")) as? Bool == true
        }
        let opened = try await browser.webView.evaluateJavaScript("window.loginPopup = window.open('about:blank', 'login'); Boolean(window.loginPopup)")
        XCTAssertEqual(opened as? Bool, true)
        try await waitUntil { !browser.popupWebViews.isEmpty }
        let popup = try XCTUnwrap(browser.popupWebViews.last)
        XCTAssertTrue(popup.configuration.websiteDataStore === browser.webView.configuration.websiteDataStore)
        let hasOpener = try await popup.evaluateJavaScript("window.opener !== null")
        XCTAssertEqual(hasOpener as? Bool, true)

        // This is the callback in HoYoLAB's public cross-login completion script.
        _ = try await popup.evaluateJavaScript("window.parent.opener.postMessage({type: 'syncLoginStatusCallback'}, '*'); true")
        try await waitUntil {
            (try? await browser.webView.evaluateJavaScript("window.loginMessage === 'syncLoginStatusCallback'")) as? Bool == true
        }
        _ = try await popup.evaluateJavaScript("window.close(); true")
        try await waitUntil { browser.popupWebViews.isEmpty }
        let parentPreserved = try await browser.webView.evaluateJavaScript("document.body.id === 'login-fixture'")
        XCTAssertEqual(parentPreserved as? Bool, true)
    }

    @MainActor
    func testPopupCookiesAreAvailableToTheAccountConnector() async throws {
        let browser = HoYoLABLoginBrowser(loginURL: URL(string: "about:blank")!)
        defer { browser.clear() }
        browser.webView.loadHTMLString("<html><body id='cookie-fixture'></body></html>", baseURL: nil)
        try await waitUntil {
            (try? await browser.webView.evaluateJavaScript("document.body && document.body.id === 'cookie-fixture'")) as? Bool == true
        }
        _ = try await browser.webView.evaluateJavaScript("window.cookiePopup = window.open('about:blank', 'cookies'); true")
        try await waitUntil { !browser.popupWebViews.isEmpty }
        let popup = try XCTUnwrap(browser.popupWebViews.last)
        for (name, value) in ["ltuid_v2": "10001", "ltoken_v2": "popup-test-token"] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: ".hoyolab.com", .path: "/", .name: name, .value: value, .secure: "TRUE"
            ]))
            await withCheckedContinuation { continuation in
                popup.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
            }
        }
        let header = await browser.cookieHeader()
        XCTAssertEqual(try HoYoLABCredentials(cookieHeader: header).accountID, "10001")
        browser.closePopup()
        XCTAssertTrue(browser.popupWebViews.isEmpty)
        let retainedHeader = await browser.cookieHeader()
        XCTAssertEqual(try HoYoLABCredentials(cookieHeader: retainedHeader).accountID, "10001")
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("WebKit login fixture timed out")
        throw URLError(.timedOut)
    }
}
