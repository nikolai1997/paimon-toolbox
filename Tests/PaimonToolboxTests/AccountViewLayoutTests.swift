import XCTest
@testable import PaimonToolbox

final class AccountViewLayoutTests: XCTestCase {
    func testVerificationPolicyAllowsOnlyExactSignInAndGeetestHosts() {
        XCTAssertTrue(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://act.mihoyo.com/bbs/event/signin")!,
            isMainFrame: true
        ))
        XCTAssertTrue(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://static.geetest.com/static/js/gt.0.5.2.js")!,
            isMainFrame: true
        ))
        XCTAssertTrue(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://api.geetest.com/get.php")!,
            isMainFrame: true
        ))
        XCTAssertTrue(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://act.mihoyo.com/bbs/event/signin")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "http://act.mihoyo.com/bbs/event/signin")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://evil-mihoyo.com/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://mihoyo.com.evil.example/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://bbs.mihoyo.com/ys/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsNavigation(
            url: URL(string: "https://bbs.miyoushe.com/ys/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://bbs.mihoyo.com/ys/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://bbs.miyoushe.com/ys/")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://sub.act.mihoyo.com/bbs/event/signin")!,
            isMainFrame: true
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://act.mihoyo.com/bbs/event/signin")!,
            isMainFrame: false
        ))
        XCTAssertFalse(MiHoYoVerificationPolicy.allowsBridgeMessage(
            pageURL: URL(string: "https://static.geetest.com/")!,
            isMainFrame: true
        ))
    }

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

    func testVerificationWebViewInjectsCookiesOnlyForExactSignInHost() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/MiHoYoVerificationWebView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("cookieDomain(for: webContext.url)"))
        XCTAssertFalse(source.contains("\".mihoyo.com\""))
        XCTAssertFalse(source.contains("\".miyoushe.com\""))
        XCTAssertFalse(source.contains("cookieDomains(for:"))
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
        XCTAssertTrue(source.contains("forMainFrameOnly: true"))
        XCTAssertTrue(source.contains("webView.navigationDelegate = context.coordinator"))
        XCTAssertTrue(source.contains("message.frameInfo.isMainFrame"))
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

    func testAccountViewExposesConfirmedLoginSyncRetryAndPreservesResignPurpose() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/AccountView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("store.canRetryConfirmedQrLoginSync"))
        XCTAssertTrue(source.contains("await store.retryConfirmedQrLoginSync()"))
        XCTAssertTrue(source.contains("Label(\"重试同步\""))
        XCTAssertTrue(source.contains("switch verification.purpose"))
        XCTAssertTrue(source.contains("await store.claimResignReward()"))
    }

    func testQrLoginSheetCancelsTasksAndAccountViewUsesConfirmedSessionID() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheetSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Views/QRCodeLoginSheet.swift"),
            encoding: .utf8
        )
        let accountSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Views/AccountView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sheetSource.contains("manualQueryTask"))
        XCTAssertTrue(sheetSource.contains("pollingTask"))
        XCTAssertTrue(sheetSource.contains(".onDisappear"))
        XCTAssertTrue(sheetSource.contains("store.cancelQrLogin(sessionID:"))
        XCTAssertTrue(accountSource.contains(".onChange(of: store.confirmedQrLoginSessionID)"))
        XCTAssertTrue(accountSource.contains("finishConfirmedQrLogin(sessionID: sessionID)"))
    }
}
