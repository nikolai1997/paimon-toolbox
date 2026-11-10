import XCTest
import WebKit
@testable import PaimonToolbox

final class OfficialMapTests: XCTestCase {
    @MainActor
    func testFloatingMapPanelRemainsAvailableBesideOtherAppsAndFullscreen() {
        _ = NSApplication.shared
        let panel = MapFloatingWindowController.makePanel()
        defer { panel.close() }
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertGreaterThanOrEqual(panel.contentMinSize.width, 380)
    }

    @MainActor
    func testLiveGuestMapLoadsRealMapTiles() async throws {
        guard ProcessInfo.processInfo.environment["PAIMON_LIVE_MAP_CHECK"] == "1" else {
            throw XCTSkip("Requires an explicit live map check")
        }
        let browser = OfficialMapBrowser()
        await browser.open(session: .guest)
        defer { browser.reset() }
        let view = try XCTUnwrap(browser.webView)
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 720)
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(1))
            let ready = try? await view.evaluateJavaScript(OfficialMapBrowser.contentReadyScript)
            let loadedTiles = try? await view.evaluateJavaScript("Array.from(document.querySelectorAll('img.leaflet-tile')).filter(i => i.complete && i.naturalWidth > 0).length")
            if ready as? Bool == true, (loadedTiles as? Int ?? 0) > 0, !browser.isLoading {
                XCTAssertNil(browser.errorMessage)
                let guideStates = try await view.evaluateJavaScript(
                    "JSON.stringify(Object.fromEntries(Object.keys(localStorage).filter(k => k.endsWith('guide-passed') || k.startsWith('user-guide-')).map(k => [k, localStorage.getItem(k)])))"
                ) as? String
                let data = try XCTUnwrap(guideStates?.data(using: .utf8))
                let states = try JSONDecoder().decode([String: String].self, from: data)
                for key in OfficialMapBrowser.completedGuideKeys {
                    XCTAssertEqual(states[key], "true", key)
                }
                try await verifyFloatingMapRoundTrip(browser: browser, view: view)
                return
            }
        }
        XCTFail("Public map did not render a loaded tile")
    }

    @MainActor
    private func verifyFloatingMapRoundTrip(browser: OfficialMapBrowser, view: WKWebView) async throws {
        _ = NSApplication.shared
        let store = AppStore()
        store.selectedSection = .map
        let controller = MapFloatingWindowController()
        defer { controller.panel?.close() }
        _ = try await view.evaluateJavaScript("window.paimonMapRoundTrip = 'same-document'")
        controller.present(store: store, browser: browser)
        XCTAssertTrue(controller.isPresented)
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        for _ in 0..<50 {
            if view.window === panel { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(view.window === panel)
        XCTAssertGreaterThan(view.bounds.width, 0)
        XCTAssertGreaterThan(view.bounds.height, 0)
        controller.present(store: store, browser: browser)
        XCTAssertTrue(controller.panel === panel)
        XCTAssertTrue(browser.webView === view)
        controller.isPinned = false
        XCTAssertEqual(panel.level, .normal)
        controller.isPinned = true
        XCTAssertEqual(panel.level, .floating)

        store.selectedSection = .cloudGame
        XCTAssertTrue(controller.isPresented)
        XCTAssertTrue(browser.webView === view)
        controller.returnToMainWindow()
        XCTAssertEqual(store.selectedSection, .map)
        XCTAssertFalse(controller.isPresented)
        XCTAssertTrue(browser.webView === view)
        let marker = try await view.evaluateJavaScript("window.paimonMapRoundTrip") as? String
        XCTAssertEqual(marker, "same-document")

        controller.present(store: store, browser: browser)
        store.selectedSection = .cloudGame
        controller.panel?.close()
        XCTAssertEqual(store.selectedSection, .cloudGame)
        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(browser.webView)
    }

    @MainActor
    func testGuidePreferencesAreInstalledBeforePageScriptsAndOnlyOnMapOrigin() async throws {
        for pageURL in [MapWebSessionContext.mapURL, URL(string: "https://example.com/")!] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.addUserScript(WKUserScript(
                source: OfficialMapBrowser.skipOnboardingScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.loadHTMLString("<html><script>window.guideAtStartup = localStorage.getItem('user-guide-passed'); localStorage.setItem('existing-marker', 'keep');</script></html>", baseURL: pageURL)
            var loaded = false
            for _ in 0..<100 {
                if (try? await view.evaluateJavaScript("typeof window.guideAtStartup !== 'undefined'")) as? Bool == true {
                    loaded = true
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(loaded)
            let guideAtStartup = try await view.evaluateJavaScript("window.guideAtStartup") as? String
            XCTAssertEqual(guideAtStartup, pageURL == MapWebSessionContext.mapURL ? "true" : nil)
            let existingMarker = try await view.evaluateJavaScript("localStorage.getItem('existing-marker')") as? String
            XCTAssertEqual(existingMarker, "keep")
            view.stopLoading()
        }
    }

    func testMapSessionIncludesWebLoginButExcludesRefreshToken() {
        let source = SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: "12345", mid: "mid", cookieToken: "cookie-value",
            ltoken: "ltoken-value", stoken: "refresh-secret"
        )
        let session = MapWebSessionContext(accountContext: source)
        XCTAssertEqual(session.accountID, "12345")
        XCTAssertTrue(session.cookies.contains { $0.name == "ltoken_v2" && $0.value == "ltoken-value" })
        XCTAssertTrue(session.cookies.contains { $0.name == "account_id_v2" && $0.value == "12345" })
        XCTAssertFalse(session.cookies.contains { $0.name.contains("stoken") || $0.name.contains("stuid") })
        XCTAssertFalse(session.cookies.contains { $0.value == "refresh-secret" })
    }

    func testMapCookiesAreSecureAndReachFirstPartyAPIs() throws {
        let session = MapWebSessionContext(accountID: "12345", cookies: [
            AccountWebCookie(name: "ltoken_v2", value: "web-token")
        ])
        let cookie = try XCTUnwrap(OfficialMapNavigationPolicy.cookies(for: session).first)
        XCTAssertTrue(cookie.isSecure)
        XCTAssertEqual(cookie.domain, ".mihoyo.com")
        XCTAssertEqual(cookie.path, "/")
        XCTAssertTrue(OfficialMapNavigationPolicy.cookies(for: .guest).isEmpty)
    }

    func testMapMainFrameCannotNavigateCredentialsToOtherPages() {
        XCTAssertTrue(OfficialMapNavigationPolicy.allows(MapWebSessionContext.mapURL, isMainFrame: true))
        for url in [
            "https://act.mihoyo.com.evil.example/ys/app/interactive-map/index.html",
            "https://evil.example/ys/app/interactive-map/index.html",
            "https://act.mihoyo.com/bbs/event/signin/",
            "http://act.mihoyo.com/ys/app/interactive-map/index.html",
            "https://act.mihoyo.com:444/ys/app/interactive-map/index.html",
            "https://name:password@act.mihoyo.com/ys/app/interactive-map/index.html",
            "mihoyobbs://open"
        ] {
            XCTAssertFalse(OfficialMapNavigationPolicy.allows(URL(string: url)!, isMainFrame: true), url)
        }
    }

    func testMapFramesAllowOfficialVerificationAndRejectDomainLookalikes() {
        XCTAssertTrue(OfficialMapNavigationPolicy.allows(URL(string: "https://api.geetest.com/get.php")!, isMainFrame: false))
        XCTAssertTrue(OfficialMapNavigationPolicy.allows(URL(string: "https://user.mihoyo.com/")!, isMainFrame: false))
        XCTAssertFalse(OfficialMapNavigationPolicy.allows(URL(string: "https://fake-mihoyo.com/")!, isMainFrame: false))
        XCTAssertFalse(OfficialMapNavigationPolicy.allows(URL(string: "https://mihoyo.com.evil.example/")!, isMainFrame: false))
    }

    func testMapSearchRoutesToSidebarDestination() {
        let results = GlobalSearchIndex.results(matching: "采集", metadata: nil, gachaRecords: [], plans: [])
        XCTAssertTrue(results.contains { $0.section == .map })
    }
}
