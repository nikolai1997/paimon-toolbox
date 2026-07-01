import XCTest

final class AccountViewLayoutTests: XCTestCase {
    func testSignedInActionsAreFloatingInsteadOfScrollContent() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ZStack(alignment: .bottomTrailing)"))
        XCTAssertTrue(source.contains("account-floating-action-bar"))
        XCTAssertFalse(source.contains("rewardGrid(summary.rewards)\n            }\n\n            actionRow"))
    }

    func testResignActionRequiresConfirmation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Label(\"补签\", systemImage: \"calendar.badge.plus\")"))
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertTrue(source.contains("await store.claimResignReward()"))
        XCTAssertTrue(source.contains("await store.completeResignVerification(result)"))
    }

    func testAccountSummaryShowsSavedAccountAvatar() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var accountAvatar: some View"))
        XCTAssertTrue(source.contains("store.accountStatus.avatarURL"))
        XCTAssertTrue(source.contains("AsyncImage(url: avatarURL)"))
        XCTAssertTrue(source.contains("person.crop.circle.fill"))
    }

    func testSignedOutCopyDescribesLocalEncryptedStorageInsteadOfKeychain() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("登录凭据加密保存到本机文件"))
        XCTAssertFalse(source.contains("本机 Keychain"))
    }

    func testVerificationWebViewProvidesSignedInBridgeContext() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/MiHoYoVerificationWebView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("case \"getUserInfo\""))
        XCTAssertTrue(source.contains("case \"getAccountInfo\""))
        XCTAssertTrue(source.contains("case \"getSelectedGameRole\""))
        XCTAssertTrue(source.contains("case \"getUserGameRole\""))
        XCTAssertTrue(source.contains("case \"getUserGameRoles\""))
        XCTAssertTrue(source.contains("case \"getGameRoles\""))
        XCTAssertTrue(source.contains("case \"getAllCookie\""))
        XCTAssertTrue(source.contains("\"x-rpc-client_type\": \"2\""))
        XCTAssertTrue(source.contains("\"miHoYo\""))
    }

    func testVerificationWebViewInjectsCookiesForMiHoYoAndMiYouSheDomains() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/MiHoYoVerificationWebView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("\".mihoyo.com\""))
        XCTAssertTrue(source.contains("\".miyoushe.com\""))
        XCTAssertTrue(source.contains("cookieDomains(for:"))
    }

    func testVerificationWebViewUsesIsolatedCookieBackedSession() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/MiHoYoVerificationWebView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("WKWebsiteDataStore.nonPersistent()"))
        XCTAssertTrue(source.contains("configuration.websiteDataStore = websiteDataStore"))
        XCTAssertTrue(source.contains("clearBrowsingData(in: webView.configuration.websiteDataStore)"))
    }

    func testVerificationWebViewPrefersSignedInWebContextOverInlineGeetest() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/MiHoYoVerificationWebView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let contextRange = try XCTUnwrap(source.range(of: "if webContext != nil"))
        let geetestRange = try XCTUnwrap(source.range(of: "guard let gt = payload.gt"))
        XCTAssertLessThan(contextRange.lowerBound, geetestRange.lowerBound)
    }

    func testClosingVerificationSheetRefreshesStatusWithoutRetryingSignIn() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let closeRange = try XCTUnwrap(source.range(of: "onClose: {"))
        let fallbackRange = try XCTUnwrap(source.range(of: "ContentUnavailableView(", range: closeRange.upperBound..<source.endIndex))
        let closeBlock = String(source[closeRange.lowerBound..<fallbackRange.lowerBound])

        XCTAssertTrue(closeBlock.contains("await store.refreshSignInStatus()"))
        XCTAssertFalse(closeBlock.contains("await store.claimDailyReward()"))
    }
}
