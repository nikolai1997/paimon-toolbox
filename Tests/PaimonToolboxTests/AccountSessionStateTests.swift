import XCTest
@testable import PaimonToolbox

final class AccountSessionStateTests: XCTestCase {
    private static let autoSignInWindowTestKey = "account.autoSignIn.window"
    private var previousAutoSignInWindowRawValue: Any?

    override func setUp() {
        super.setUp()
        previousAutoSignInWindowRawValue = UserDefaults.standard.object(forKey: Self.autoSignInWindowTestKey)
        UserDefaults.standard.removeObject(forKey: Self.autoSignInWindowTestKey)
    }

    override func tearDown() {
        if let previousAutoSignInWindowRawValue {
            UserDefaults.standard.set(previousAutoSignInWindowRawValue, forKey: Self.autoSignInWindowTestKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.autoSignInWindowTestKey)
        }
        previousAutoSignInWindowRawValue = nil
        super.tearDown()
    }

    func testMetadataMapsToSignedInStatus() {
        let account = MiHoYoAccount(
            accountID: "10001",
            mid: "mid",
            nickname: "旅行者",
            avatarURL: URL(string: "https://bbs-static.miyoushe.com/avatar/avatar123.png")
        )
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let metadata = AccountMetadata(account: account, selectedRole: role, lastSummary: nil)
        let status = LocalAccountSessionService.status(from: metadata)
        XCTAssertTrue(status.isSignedIn)
        XCTAssertEqual(status.nickname, "旅行者")
        XCTAssertEqual(status.avatarURL?.absoluteString, "https://bbs-static.miyoushe.com/avatar/avatar123.png")
        XCTAssertEqual(status.selectedRole?.uid, "100000001")
    }

    @MainActor
    func testVerificationContextUsesSavedAccountAvatarURL() throws {
        let metadata = AccountMetadata(
            account: MiHoYoAccount(
                accountID: "10001",
                mid: "mid",
                nickname: "派蒙",
                avatarURL: URL(string: "https://bbs-static.miyoushe.com/avatar/avatar123.png")
            ),
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            lastSummary: nil
        )
        let metadataStore = MockMetadataStore(metadata: metadata)
        let secretStore = MockSecretStore(
            secretsByAccountID: [
                "10001": AccountSecrets(stuid: "10001", stoken: "stoken", mid: "mid", cookieToken: "cookie-token", ltoken: "ltoken")
            ]
        )
        let service = LocalAccountSessionService(metadataStore: metadataStore, secretStore: secretStore)

        let context = try service.signInWebVerificationContext()

        XCTAssertEqual(context.nickname, "派蒙")
        XCTAssertEqual(context.avatarURL?.absoluteString, "https://bbs-static.miyoushe.com/avatar/avatar123.png")
        XCTAssertEqual(context.userInfo["avatar_url"] as? String, "https://bbs-static.miyoushe.com/avatar/avatar123.png")
    }

    @MainActor
    func testLoadStatusClearsMetadataWhenSecretIsMissing() {
        let metadataStore = MockMetadataStore(
            metadata: AccountMetadata(
                account: MiHoYoAccount(accountID: "10001", mid: "mid", nickname: "旅行者"),
                selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
                lastSummary: nil
            )
        )
        let secretStore = MockSecretStore()
        let service = LocalAccountSessionService(metadataStore: metadataStore, secretStore: secretStore)

        let status = service.loadStatus()

        XCTAssertEqual(status, .signedOut)
        XCTAssertEqual(metadataStore.clearCallCount, 1)
        XCTAssertNil(try? metadataStore.load())
    }

    func testValidateClaimResultThrowsWhenVerificationIsRequired() {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: "gt-value", challenge: "challenge-value")

        XCTAssertThrowsError(try LocalAccountSessionService.validateClaimResult(payload)) { error in
            guard case let AccountSessionError.requiresVerification(result) = error else {
                return XCTFail("Expected requiresVerification, got \(error)")
            }
            XCTAssertEqual(result, payload)
        }
    }

    func testValidateClaimResultThrowsWhenRiskFlagIsReturnedWithoutRiskCode() {
        let payload = SignInResultPayload(success: 1, riskCode: nil, isRisk: true, gt: nil, challenge: nil)

        XCTAssertThrowsError(try LocalAccountSessionService.validateClaimResult(payload)) { error in
            guard case let AccountSessionError.requiresVerification(result) = error else {
                return XCTFail("Expected requiresVerification, got \(error)")
            }
            XCTAssertTrue(result.isRisk == true)
        }
    }

    func testValidateClaimResultRejectsEmptyOrUnknownResponse() {
        let empty = SignInResultPayload(success: nil, riskCode: nil, gt: nil, challenge: nil)
        let unknown = SignInResultPayload(code: "pending", success: nil, riskCode: nil, gt: nil, challenge: nil)

        for payload in [empty, unknown] {
            XCTAssertThrowsError(try LocalAccountSessionService.validateClaimResult(payload)) { error in
                guard case AccountSessionError.invalidResponse = error else {
                    return XCTFail("Expected invalidResponse, got \(error)")
                }
            }
        }
    }

    func testValidateClaimResultAcceptsExplicitSuccess() {
        XCTAssertNoThrow(try LocalAccountSessionService.validateClaimResult(
            SignInResultPayload(success: 0, riskCode: nil, gt: nil, challenge: nil)
        ))
        XCTAssertNoThrow(try LocalAccountSessionService.validateClaimResult(
            SignInResultPayload(code: "ok", success: nil, riskCode: nil, gt: nil, challenge: nil)
        ))
    }

    func testDefaultAccountStoresReportInitializationFailureInsteadOfUsingEphemeralStorage() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Services/AccountSessionService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("UnavailableAccountMetadataStore"))
        XCTAssertTrue(source.contains("UnavailableAccountSecretStore"))
        XCTAssertFalse(source.contains("return EphemeralAccountMetadataStore()"))
        XCTAssertFalse(source.contains("return EphemeralAccountSecretStore()"))
    }

    func testAccountSessionErrorKeepsStructuredAPIRetcode() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Services/AccountSessionError.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("case apiFailureResponse(retcode: Int, message: String)"))
        XCTAssertTrue(source.contains("var apiRetcode: Int?"))
    }

    @MainActor
    func testAppStoreClaimDailyRewardStoresStructuredVerificationState() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: "gt-value", challenge: "challenge-value")
        let webContext = SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: "10001",
            cookieToken: "cookie-token",
            ltoken: "ltoken"
        )
        let accountService = MockAccountSessionService()
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        accountService.webVerificationContext = webContext
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            signInRiskConfirmationDelayNanoseconds: 0
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.claimDailyReward()

        XCTAssertEqual(store.accountVerification?.message, AccountSessionError.requiresVerification(payload).localizedDescription)
        XCTAssertEqual(store.accountVerification?.url, HoYoConstants.signInVerificationURL)
        XCTAssertEqual(store.accountVerification?.payload, payload)
        XCTAssertEqual(store.accountVerification?.webContext, webContext)
        XCTAssertEqual(store.accountVerification?.purpose, .dailySignIn)
        XCTAssertEqual(store.errorMessage, AccountSessionError.requiresVerification(payload).localizedDescription)
        XCTAssertNil(store.successMessage)
    }

    @MainActor
    func testLoadStoresResignInfoWhenAccountIsSignedIn() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.resignInfoResult = Self.resignInfo(canResign: true)
        let store = AppStore(accountService: accountService)

        await store.load(autoRefreshRemoteMetadata: false)

        XCTAssertEqual(accountService.loadResignInfoCallCount, 1)
        XCTAssertEqual(store.accountResignInfo?.signCountMissed, 2)
        XCTAssertTrue(store.accountResignInfo?.canResign == true)
    }

    @MainActor
    func testClaimResignRewardRefreshesStatusAndResignInfo() async {
        let accountService = MockAccountSessionService()
        accountService.claimResignRewardResult = Self.signedInStatus(isTodaySigned: false)
        accountService.resignInfoResult = Self.resignInfo(canResign: false, signed: true)
        let store = AppStore(accountService: accountService)

        await store.claimResignReward()

        XCTAssertEqual(accountService.claimResignRewardCallCount, 1)
        XCTAssertEqual(accountService.loadResignInfoCallCount, 1)
        XCTAssertEqual(store.successMessage, "补签完成")
        XCTAssertFalse(store.accountResignInfo?.canResign == true)
    }

    @MainActor
    func testClaimResignRewardDoesNotCompleteUntilRefreshedInfoConfirmsSigned() async {
        let accountService = MockAccountSessionService()
        accountService.claimResignRewardResult = Self.signedInStatus(isTodaySigned: false)
        accountService.resignInfoResult = Self.resignInfo(canResign: false, signed: false)
        let store = AppStore(accountService: accountService)

        await store.claimResignReward()

        XCTAssertNil(store.successMessage)
        XCTAssertTrue(store.errorMessage?.contains("补签状态未确认成功") == true)
    }

    @MainActor
    func testClaimResignRewardStoresStructuredVerificationState() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: "gt-value", challenge: "challenge-value")
        let webContext = SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: "10001",
            cookieToken: "cookie-token",
            ltoken: "ltoken"
        )
        let accountService = MockAccountSessionService()
        accountService.claimResignError = AccountSessionError.requiresVerification(payload)
        accountService.webVerificationContext = webContext
        let store = AppStore(accountService: accountService)

        await store.claimResignReward()

        XCTAssertEqual(store.accountVerification?.payload, payload)
        XCTAssertEqual(store.accountVerification?.webContext, webContext)
        XCTAssertEqual(store.accountVerification?.purpose, .resign)
        XCTAssertEqual(store.errorMessage, AccountSessionError.requiresVerification(payload).localizedDescription)
        XCTAssertNil(store.successMessage)
    }

    @MainActor
    func testLoadSkipsAutoSignInWhenSettingIsDisabled() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: false)
        let autoSignInStore = MockAutoSignInStore(isEnabled: false)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        tokenRefreshStore.setLastRefreshDate(Date(timeIntervalSince1970: 1_788_476_400), accountID: "10001")
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore, tokenRefreshStore: tokenRefreshStore)

        await store.load(autoRefreshRemoteMetadata: false)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 0)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
        XCTAssertNil(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"))
    }

    @MainActor
    func testLoadRefreshesLoginTokensWhenRefreshIsStale() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: true)
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: true)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        tokenRefreshStore.setLastRefreshDate(Date(timeIntervalSince1970: 1_788_390_000), accountID: "10001")
        let store = AppStore(accountService: accountService, tokenRefreshStore: tokenRefreshStore)

        await store.load(autoRefreshRemoteMetadata: false, now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(tokenRefreshStore.lastRefreshDate(accountID: "10001"), Date(timeIntervalSince1970: 1_788_480_000))
    }

    @MainActor
    func testLoadSkipsLoginTokenRefreshWhenRefreshIsRecent() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: true)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        tokenRefreshStore.setLastRefreshDate(Date(timeIntervalSince1970: 1_788_476_400), accountID: "10001")
        let store = AppStore(accountService: accountService, tokenRefreshStore: tokenRefreshStore)

        await store.load(autoRefreshRemoteMetadata: false, now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 0)
    }

    @MainActor
    func testLoadAutomaticallySignsInOnceWhenScheduledTimeHasArrived() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 4, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-04")
        )
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            tokenRefreshStore: tokenRefreshStore
        )

        await store.load(autoRefreshRemoteMetadata: false, now: now)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertEqual(store.successMessage, "自动签到完成")
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-04")
    }

    @MainActor
    func testAutomaticSignInCheckRunsAfterAppStaysOpenAcrossDays() async {
        let accountService = MockAccountSessionService()
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        autoSignInStore.setCompletedDay("cn_gf01:2026-09-04", accountID: "10001", uid: "100000001")
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            tokenRefreshStore: tokenRefreshStore
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.successMessage, "自动签到完成")
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-05")
    }

    @MainActor
    func testAutomaticSignInSchedulesMorningTimeAndSkipsNetworkBeforeIt() async {
        let accountService = MockAccountSessionService()
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 7)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 0)
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 0)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
        let scheduled = autoSignInStore.scheduledAttemptDate(
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        XCTAssertNotNil(scheduled)
        guard let scheduledDate = scheduled else { return }
        XCTAssertGreaterThan(scheduledDate, now)
        let components = Self.cnCalendar.dateComponents([.hour], from: scheduledDate)
        XCTAssertGreaterThanOrEqual(components.hour ?? 0, AutoSignInSettings.morningWindowStartHour)
        XCTAssertLessThan(components.hour ?? 24, AutoSignInSettings.morningWindowEndHour)
    }

    @MainActor
    func testAutomaticSignInSkipsNetworkBeforeSavedScheduledTime() async {
        let accountService = MockAccountSessionService()
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 9)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(30 * 60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 0)
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 0)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
    }

    @MainActor
    func testAutomaticSignInRefreshesTokenAndRetriesOnceWhenLoginExpired() async {
        let accountService = MockAccountSessionService()
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResults = [
            .failure(AccountSessionError.apiFailure("登录状态失效，请重新登录")),
            .success(Self.signedInStatus(isTodaySigned: false))
        ]
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        tokenRefreshStore.setLastRefreshDate(now.addingTimeInterval(-10 * 60), accountID: "10001")
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            tokenRefreshStore: tokenRefreshStore
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 2)
        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.successMessage, "自动签到完成")
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-05")
    }

    @MainActor
    func testAutomaticSignInTreatsRiskResponseAsSuccessWhenStatusRefreshShowsSigned() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil)
        let accountService = MockAccountSessionService()
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResults = [
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 2)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertNil(store.accountVerification)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.successMessage, "自动签到完成")
        XCTAssertNil(autoSignInStore.lastFailureDate(accountID: "10001", uid: "100000001"))
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-05")
    }

    @MainActor
    func testAutomaticSignInWaitsBeforeShowingVerificationWhenRiskStatusIsDelayed() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil)
        let accountService = MockAccountSessionService()
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResults = [
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let sleepRecorder = SleepCallRecorder()
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            signInRiskConfirmationDelayNanoseconds: 99,
            sleep: { nanoseconds in
                await sleepRecorder.append(nanoseconds)
            }
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        let sleepCalls = await sleepRecorder.calls
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 3)
        XCTAssertEqual(sleepCalls, [99])
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertNil(store.accountVerification)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.successMessage, "自动签到完成")
    }

    @MainActor
    func testManualSignInRefreshesStatusAndSkipsClaimWhenAlreadySignedToday() async {
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.claimDailyReward(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
        XCTAssertEqual(store.successMessage, "今日已签到")
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-04")
    }

    @MainActor
    func testManualSignInRefreshesStatusBeforeClaimingWhenUnsigned() async {
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.claimDailyReward(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.successMessage, "签到完成")
    }

    @MainActor
    func testManualSignInDoesNotCompleteWhenClaimRefreshRemainsUnsigned() async {
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: false)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)

        await store.claimDailyReward(now: now)

        XCTAssertNil(store.successMessage)
        XCTAssertTrue(store.errorMessage?.contains("签到状态未确认成功") == true)
        XCTAssertNil(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"))
    }

    @MainActor
    func testAutomaticSignInDoesNotCompleteWhenClaimRefreshRemainsUnsigned() async {
        let accountService = MockAccountSessionService()
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: false)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-05")
        )
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.runAutomaticSignInCheck(now: now)

        XCTAssertNil(store.successMessage)
        XCTAssertTrue(store.errorMessage?.contains("签到状态未确认成功") == true)
        XCTAssertNil(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"))
    }

    @MainActor
    func testManualSignInTreatsRiskResponseAsSuccessWhenStatusRefreshShowsSigned() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil)
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResults = [
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)

        await store.claimDailyReward(now: now)

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 2)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertNil(store.accountVerification)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.successMessage, "签到完成")
        XCTAssertNil(autoSignInStore.lastFailureDate(accountID: "10001", uid: "100000001"))
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-05")
    }

    @MainActor
    func testManualSignInWaitsBeforeShowingVerificationWhenRiskStatusIsDelayed() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil)
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResults = [
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: false)),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let sleepRecorder = SleepCallRecorder()
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            signInRiskConfirmationDelayNanoseconds: 42,
            sleep: { nanoseconds in
                await sleepRecorder.append(nanoseconds)
            }
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)
        let now = Self.cnDate(year: 2026, month: 9, day: 5, hour: 10)

        await store.claimDailyReward(now: now)

        let sleepCalls = await sleepRecorder.calls
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 3)
        XCTAssertEqual(sleepCalls, [42])
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertNil(store.accountVerification)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.successMessage, "签到完成")
        XCTAssertNil(autoSignInStore.lastFailureDate(accountID: "10001", uid: "100000001"))
        XCTAssertEqual(autoSignInStore.completedDay(accountID: "10001", uid: "100000001"), "cn_gf01:2026-09-05")
    }

    @MainActor
    func testManualSignInSkipsClaimDuringFailureCooldown() async {
        let accountService = MockAccountSessionService()
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        autoSignInStore.setLastFailureDate(
            Date(timeIntervalSince1970: 1_788_479_700),
            accountID: "10001",
            uid: "100000001"
        )
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.claimDailyReward(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 0)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
        XCTAssertEqual(store.errorMessage, "签到刚刚失败过，请稍后再试，避免频繁请求触发风控。")
    }

    @MainActor
    func testClaimFailureStoresCooldownTimestamp() async {
        let payload = SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil)
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimError = AccountSessionError.requiresVerification(payload)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            signInRiskConfirmationDelayNanoseconds: 0
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)
        let now = Date(timeIntervalSince1970: 1_788_480_000)

        await store.claimDailyReward(now: now)

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 3)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(autoSignInStore.lastFailureDate(accountID: "10001", uid: "100000001"), now)
        XCTAssertNotNil(store.accountVerification)
    }

    @MainActor
    func testRefreshSignInStatusRefreshesTokenAndRetriesOnceWhenLoginExpired() async {
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResults = [
            .failure(AccountSessionError.apiFailure("登录状态失效，请重新登录")),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        let store = AppStore(accountService: accountService, tokenRefreshStore: tokenRefreshStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.refreshSignInStatus(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 2)
        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertEqual(tokenRefreshStore.lastRefreshDate(accountID: "10001"), Date(timeIntervalSince1970: 1_788_480_000))
        XCTAssertEqual(store.successMessage, "签到状态已刷新")
    }

    @MainActor
    func testRefreshSignInStatusUsesStructuredExpiredRetcodeWithoutLegacyMessage() async {
        let accountService = MockAccountSessionService()
        accountService.refreshSignInStatusResults = [
            .failure(AccountSessionError.apiFailureResponse(retcode: -100, message: "session rejected")),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        let store = AppStore(accountService: accountService, tokenRefreshStore: tokenRefreshStore)
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.refreshSignInStatus(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 2)
        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 1)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
    }

    @MainActor
    func testClaimDailyRewardRefreshesTokenAndRetriesOnceWhenLoginExpired() async {
        let accountService = MockAccountSessionService()
        accountService.claimDailyRewardResults = [
            .failure(AccountSessionError.apiFailure("cookie token 失效")),
            .success(Self.signedInStatus(isTodaySigned: true))
        ]
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshLoginTokensResult = Self.signedInStatus(isTodaySigned: false)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let tokenRefreshStore = MockAccountTokenRefreshStore()
        let store = AppStore(
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            tokenRefreshStore: tokenRefreshStore
        )
        store.accountStatus = Self.signedInStatus(isTodaySigned: false)

        await store.claimDailyReward(now: Date(timeIntervalSince1970: 1_788_480_000))

        XCTAssertEqual(accountService.claimDailyRewardCallCount, 2)
        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 2)
        XCTAssertEqual(store.accountStatus.signInSummary?.isTodaySigned, true)
        XCTAssertEqual(store.successMessage, "签到完成")
    }

    @MainActor
    func testLoadDoesNotRepeatAutoSignInAfterAttemptToday() async {
        let accountService = MockAccountSessionService()
        accountService.loadStatusResult = Self.signedInStatus(isTodaySigned: false)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        autoSignInStore.setCompletedDay("cn_gf01:2026-09-04", accountID: "10001", uid: "100000001")
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        let now = Date(timeIntervalSince1970: 1_788_480_000)

        await store.load(autoRefreshRemoteMetadata: false, now: now)

        XCTAssertEqual(accountService.refreshLoginTokensCallCount, 0)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 0)
    }

    @MainActor
    func testFinishConfirmedQrLoginRunsAutoSignInWhenEnabled() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeQrLoginResult = Self.signedInStatus(isTodaySigned: false)
        accountService.refreshSignInStatusResult = Self.signedInStatus(isTodaySigned: false)
        accountService.claimDailyRewardResult = Self.signedInStatus(isTodaySigned: true)
        let autoSignInStore = MockAutoSignInStore(isEnabled: true)
        let now = Self.cnDate(year: 2026, month: 9, day: 4, hour: 10)
        autoSignInStore.setScheduledAttemptDate(
            now.addingTimeInterval(-60),
            accountID: "10001",
            uid: "100000001",
            serverDay: Self.scheduledAttemptIdentifier("cn_gf01:2026-09-04")
        )
        let store = AppStore(accountService: accountService, autoSignInStore: autoSignInStore)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID

        await store.finishConfirmedQrLogin(sessionID: sessionID, now: now)

        XCTAssertEqual(accountService.completeQrLoginResultCallCount, 1)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
        XCTAssertEqual(store.successMessage, "自动签到完成")
    }

    @MainActor
    func testStartQrLoginClearsStructuredVerificationState() async {
        let accountService = MockAccountSessionService()
        accountService.startQrLoginResult = QrLoginSession(
            qrURL: URL(string: "https://example.com/qr")!,
            ticket: "ticket-1"
        )
        let store = AppStore(accountService: accountService)
        store.accountVerification = AccountVerificationState(
            message: "需要验证",
            url: HoYoConstants.signInVerificationURL,
            payload: SignInResultPayload(success: 0, riskCode: -5003, gt: nil, challenge: nil),
            webContext: nil
        )

        await store.startQrLogin()

        XCTAssertNil(store.accountVerification)
        XCTAssertEqual(store.qrLoginState, .waiting)
        XCTAssertEqual(store.qrLoginSession?.ticket, "ticket-1")
    }

    @MainActor
    func testCanceledQrLoginIgnoresLateConfirmedQueryResult() async throws {
        let confirmed = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let queryStarted = expectation(description: "QR query started")
        let deferredQuery = DeferredQrLoginQuery()
        let accountService = MockAccountSessionService()
        accountService.startQrLoginResult = QrLoginSession(
            qrURL: URL(string: "https://example.com/qr")!,
            ticket: "ticket-1"
        )
        accountService.queryQrLoginHandler = { _ in
            queryStarted.fulfill()
            return await deferredQuery.wait()
        }
        let store = AppStore(accountService: accountService)
        await store.startQrLogin()
        let sessionID = try XCTUnwrap(store.qrLoginSessionID)

        let queryTask = Task {
            await store.queryQrLogin(ticket: "ticket-1", sessionID: sessionID)
        }
        await fulfillment(of: [queryStarted], timeout: 1)
        store.cancelQrLogin(sessionID: sessionID)
        await deferredQuery.resume(with: confirmed)
        await queryTask.value

        XCTAssertNil(store.qrLoginSession)
        XCTAssertNil(store.qrLoginSessionID)
        XCTAssertNil(store.confirmedQrLoginResult)
        XCTAssertNil(store.confirmedQrLoginSessionID)
        XCTAssertEqual(store.qrLoginState, .canceled)
        XCTAssertEqual(accountService.completeQrLoginResultCallCount, 0)
    }

    @MainActor
    func testRefreshLoginTokensKeepsOldSecretsWhenCandidateSummaryFails() async throws {
        let accountID = "10001"
        let oldSecrets = AccountSecrets(
            stuid: accountID,
            stoken: "stoken-value",
            mid: "mid-value",
            cookieToken: "old-cookie",
            ltoken: "old-ltoken"
        )
        let metadataStore = MockMetadataStore(metadata: AccountMetadata(
            account: MiHoYoAccount(accountID: accountID, mid: "mid-value", nickname: "旅行者"),
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            lastSummary: nil
        ))
        let secretStore = RecordingSecretStore(accountID: accountID, secrets: oldSecrets)
        AccountSessionURLProtocol.requestHandler = { request in
            let path = request.url?.path() ?? ""
            let body: String
            let statusCode: Int
            switch path {
            case let value where value.hasSuffix("/getLTokenBySToken"):
                statusCode = 200
                body = #"{"retcode":0,"message":"OK","data":{"ltoken":"new-ltoken"}}"#
            case let value where value.hasSuffix("/getCookieAccountInfoBySToken"):
                statusCode = 200
                body = #"{"retcode":0,"message":"OK","data":{"uid":"10001","cookie_token":"new-cookie"}}"#
            default:
                statusCode = 500
                body = #"{"message":"summary unavailable"}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { AccountSessionURLProtocol.requestHandler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountSessionURLProtocol.self]
        let httpClient = HoYoHTTPClient(session: URLSession(configuration: configuration))
        let service = LocalAccountSessionService(
            metadataStore: metadataStore,
            secretStore: secretStore,
            passportClient: MiHoYoPassportClient(httpClient: httpClient),
            signInClient: GenshinSignInClient(httpClient: httpClient)
        )

        do {
            _ = try await service.refreshLoginTokens()
            XCTFail("Expected candidate summary validation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP 500"))
        }

        XCTAssertEqual(try secretStore.load(accountID: accountID), oldSecrets)
        XCTAssertEqual(secretStore.saveCallCount, 0)
    }

    @MainActor
    func testFinishConfirmedQrLoginFailureDoesNotMarkQrCodeFailed() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeError = AccountSessionError.apiFailure("登录状态失效，请重新登录")
        let store = AppStore(accountService: accountService)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID
        store.qrLoginState = .confirmed

        await store.finishConfirmedQrLogin(sessionID: sessionID)

        XCTAssertEqual(store.qrLoginState, .confirmed)
        XCTAssertEqual(store.errorMessage, "登录已确认，但同步账号数据失败：接口返回错误：登录状态失效，请重新登录")
    }

    @MainActor
    func testFinishConfirmedQrLoginShowsSyncStepFailure() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeError = AccountSessionError.stepFailed("获取 CookieToken", "接口返回错误：登录状态失效，请重新登录")
        let store = AppStore(accountService: accountService)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID
        store.qrLoginState = .confirmed

        await store.finishConfirmedQrLogin(sessionID: sessionID)

        XCTAssertEqual(store.errorMessage, "登录已确认，但同步账号数据失败：获取 CookieToken失败：接口返回错误：登录状态失效，请重新登录")
    }

    @MainActor
    func testConfirmedQrLoginSyncCanRetryWithoutCreatingANewQRCode() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeError = AccountSessionError.apiFailure("temporary failure")
        let store = AppStore(accountService: accountService)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID
        store.qrLoginState = .confirmed

        await store.finishConfirmedQrLogin(sessionID: sessionID)

        XCTAssertTrue(store.canRetryConfirmedQrLoginSync)
        XCTAssertNotNil(store.confirmedQrLoginResult)

        accountService.completeError = nil
        accountService.completeQrLoginResult = Self.signedInStatus(isTodaySigned: false)
        await store.retryConfirmedQrLoginSync()

        XCTAssertEqual(accountService.completeQrLoginResultCallCount, 2)
        XCTAssertNil(store.confirmedQrLoginResult)
        XCTAssertTrue(store.accountStatus.isSignedIn)
        XCTAssertFalse(store.canRetryConfirmedQrLoginSync)
    }

    @MainActor
    func testConfirmedQrLoginRetrySurvivesUnrelatedGlobalMessageChanges() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeError = AccountSessionError.apiFailure("temporary failure")
        let store = AppStore(accountService: accountService)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID
        store.qrLoginState = .confirmed

        await store.finishConfirmedQrLogin(sessionID: sessionID)
        store.errorMessage = "另一个功能的错误"

        XCTAssertNotNil(store.qrLoginSyncError)
        XCTAssertTrue(store.canRetryConfirmedQrLoginSync)
    }

    @MainActor
    func testFinishConfirmedQrLoginCancellationKeepsPendingResultForRetry() async {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let accountService = MockAccountSessionService()
        accountService.completeError = CancellationError()
        let store = AppStore(accountService: accountService)
        let sessionID = UUID()
        store.qrLoginSessionID = sessionID
        store.confirmedQrLoginResult = result
        store.confirmedQrLoginSessionID = sessionID
        store.qrLoginState = .confirmed

        await store.finishConfirmedQrLogin(sessionID: sessionID)

        XCTAssertEqual(store.qrLoginState, .confirmed)
        XCTAssertNotNil(store.confirmedQrLoginResult)
        XCTAssertEqual(store.errorMessage, "登录已确认，正在同步账号数据，请稍候。")
    }

    @MainActor
    func testSignOutKeepsMetadataWhenSecretDeleteFails() throws {
        let metadata = AccountMetadata(
            account: MiHoYoAccount(accountID: "10001", mid: "mid", nickname: "旅行者"),
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            lastSummary: nil
        )
        let metadataStore = MockMetadataStore(metadata: metadata)
        let secretStore = MockSecretStore(
            secretsByAccountID: [
                "10001": AccountSecrets(stuid: "10001", stoken: "stoken", mid: "mid", cookieToken: nil, ltoken: nil)
            ],
            deleteError: AccountSessionError.localStorageUnavailable("fixture delete failure")
        )
        let service = LocalAccountSessionService(metadataStore: metadataStore, secretStore: secretStore)

        XCTAssertThrowsError(try service.signOut()) { error in
            guard case AccountSessionError.localStorageUnavailable("fixture delete failure") = error else {
                return XCTFail("Expected localStorageUnavailable, got \\(error)")
            }
        }
        XCTAssertEqual(metadataStore.clearCallCount, 0)
        XCTAssertEqual(try metadataStore.load()?.account.accountID, "10001")
    }

    private static var cnCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    private static func cnDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        cnCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func scheduledAttemptIdentifier(
        _ serverDay: String,
        window: AutoSignInWindow = .morning
    ) -> String {
        AutoSignInSettings.scheduledAttemptIdentifier(serverDay: serverDay, window: window)
    }

    private static func signedInStatus(isTodaySigned: Bool) -> LocalAccountStatus {
        LocalAccountStatus(
            isSignedIn: true,
            nickname: "旅行者",
            accountID: "10001",
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            signInSummary: SignInSummary(uid: "100000001", month: 9, totalSignDay: isTodaySigned ? 3 : 2, isTodaySigned: isTodaySigned, rewards: []),
            sessionMessage: nil,
            lastCheckInDate: nil
        )
    }

    private static func resignInfo(canResign: Bool, signed: Bool = false) -> SignInResignInfoPayload {
        SignInResignInfoPayload(
            resignCountDaily: canResign ? 0 : 1,
            resignCountMonthly: canResign ? 1 : 3,
            resignLimitDaily: 1,
            resignLimitMonthly: 3,
            signCountMissed: canResign ? 2 : 0,
            coinCount: canResign ? 5 : 0,
            coinCost: 1,
            rule: "rule",
            signed: signed,
            signDays: 7,
            cost: 0,
            monthQualityCount: 0,
            qualityCount: 0
        )
    }
}

private final class MockMetadataStore: AccountMetadataStoring {
    private var metadata: AccountMetadata?
    private(set) var clearCallCount = 0

    init(metadata: AccountMetadata? = nil) {
        self.metadata = metadata
    }

    func load() throws -> AccountMetadata? {
        metadata
    }

    func save(_ metadata: AccountMetadata) throws {
        self.metadata = metadata
    }

    func clear() throws {
        clearCallCount += 1
        metadata = nil
    }
}

@MainActor
private final class MockAccountSessionService: AccountSessionServicing {
    var startQrLoginResult: QrLoginSession?
    var queryQrLoginResult: QrLoginResultPayload?
    var queryQrLoginHandler: ((String) async throws -> QrLoginResultPayload)?
    var completeQrLoginResult: LocalAccountStatus = .signedOut
    var refreshSignInStatusResult: LocalAccountStatus = .signedOut
    var refreshLoginTokensResult: LocalAccountStatus?
    var claimDailyRewardResult: LocalAccountStatus = .signedOut
    var claimResignRewardResult: LocalAccountStatus = .signedOut
    var resignInfoResult: SignInResignInfoPayload?
    var signOutResult: LocalAccountStatus = .signedOut
    var loadStatusResult: LocalAccountStatus = .signedOut
    var startError: Error?
    var completeError: Error?
    var refreshError: Error?
    var claimError: Error?
    var claimResignError: Error?
    var signOutError: Error?
    var webVerificationContext: SignInWebVerificationContext?
    var refreshSignInStatusResults: [Result<LocalAccountStatus, Error>] = []
    var claimDailyRewardResults: [Result<LocalAccountStatus, Error>] = []
    private(set) var refreshLoginTokensCallCount = 0
    private(set) var refreshSignInStatusCallCount = 0
    private(set) var claimDailyRewardCallCount = 0
    private(set) var claimResignRewardCallCount = 0
    private(set) var loadResignInfoCallCount = 0
    private(set) var completeQrLoginResultCallCount = 0

    func loadStatus() -> LocalAccountStatus { loadStatusResult }

    func startQrLogin() async throws -> QrLoginSession {
        if let startError { throw startError }
        guard let startQrLoginResult else {
            throw AccountSessionError.invalidResponse("missing startQrLoginResult")
        }
        return startQrLoginResult
    }

    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload {
        if let queryQrLoginHandler {
            return try await queryQrLoginHandler(ticket)
        }
        if let completeError { throw completeError }
        guard let queryQrLoginResult else {
            throw AccountSessionError.invalidResponse("missing queryQrLoginResult")
        }
        return queryQrLoginResult
    }

    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus {
        completeQrLoginResultCallCount += 1
        if let completeError { throw completeError }
        return completeQrLoginResult
    }

    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus {
        if let completeError { throw completeError }
        return completeQrLoginResult
    }

    func refreshSignInStatus() async throws -> LocalAccountStatus {
        refreshSignInStatusCallCount += 1
        if !refreshSignInStatusResults.isEmpty {
            return try refreshSignInStatusResults.removeFirst().get()
        }
        if let refreshError { throw refreshError }
        return refreshSignInStatusResult
    }

    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus {
        claimDailyRewardCallCount += 1
        if !claimDailyRewardResults.isEmpty {
            return try claimDailyRewardResults.removeFirst().get()
        }
        if let claimError { throw claimError }
        return claimDailyRewardResult
    }

    func loadResignInfo() async throws -> SignInResignInfoPayload {
        loadResignInfoCallCount += 1
        guard let resignInfoResult else {
            throw AccountSessionError.missingAccount
        }
        return resignInfoResult
    }

    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus {
        claimResignRewardCallCount += 1
        if let claimResignError { throw claimResignError }
        return claimResignRewardResult
    }

    func refreshLoginTokens() async throws -> LocalAccountStatus {
        refreshLoginTokensCallCount += 1
        if let refreshError { throw refreshError }
        return refreshLoginTokensResult ?? loadStatusResult
    }

    func signInWebVerificationContext() throws -> SignInWebVerificationContext {
        guard let webVerificationContext else {
            throw AccountSessionError.missingAccount
        }
        return webVerificationContext
    }

    func loadGachaRecords() async throws -> [GachaRecord] {
        []
    }

    func signOut() throws -> LocalAccountStatus {
        if let signOutError { throw signOutError }
        return signOutResult
    }
}

private actor DeferredQrLoginQuery {
    private var continuation: CheckedContinuation<QrLoginResultPayload, Never>?
    private var bufferedResult: QrLoginResultPayload?

    func wait() async -> QrLoginResultPayload {
        if let bufferedResult {
            self.bufferedResult = nil
            return bufferedResult
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: QrLoginResultPayload) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: result)
        } else {
            bufferedResult = result
        }
    }
}

private final class RecordingSecretStore: AccountSecretStoring {
    private var secretsByAccountID: [String: AccountSecrets]
    private(set) var saveCallCount = 0

    init(accountID: String, secrets: AccountSecrets) {
        secretsByAccountID = [accountID: secrets]
    }

    func load(accountID: String) throws -> AccountSecrets? {
        secretsByAccountID[accountID]
    }

    func save(_ secrets: AccountSecrets, accountID: String) throws {
        saveCallCount += 1
        secretsByAccountID[accountID] = secrets
    }

    func delete(accountID: String) throws {
        secretsByAccountID.removeValue(forKey: accountID)
    }
}

private final class AccountSessionURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor SleepCallRecorder {
    private var recordedCalls: [UInt64] = []

    var calls: [UInt64] {
        recordedCalls
    }

    func append(_ nanoseconds: UInt64) {
        recordedCalls.append(nanoseconds)
    }
}

private final class MockAutoSignInStore: AutoSignInStoring {
    var isEnabled: Bool
    private var completedDays: [String: String] = [:]
    private var failureDates: [String: Date] = [:]
    private var scheduledAttemptDates: [String: Date] = [:]

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func completedDay(accountID: String, uid: String) -> String? {
        completedDays[key(accountID: accountID, uid: uid)]
    }

    func setCompletedDay(_ day: String, accountID: String, uid: String) {
        completedDays[key(accountID: accountID, uid: uid)] = day
    }

    func lastFailureDate(accountID: String, uid: String) -> Date? {
        failureDates[key(accountID: accountID, uid: uid)]
    }

    func setLastFailureDate(_ date: Date?, accountID: String, uid: String) {
        let key = key(accountID: accountID, uid: uid)
        if let date {
            failureDates[key] = date
        } else {
            failureDates.removeValue(forKey: key)
        }
    }

    func scheduledAttemptDate(accountID: String, uid: String, serverDay: String) -> Date? {
        scheduledAttemptDates[scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay)]
    }

    func setScheduledAttemptDate(_ date: Date, accountID: String, uid: String, serverDay: String) {
        scheduledAttemptDates[scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay)] = date
    }

    private func key(accountID: String, uid: String) -> String {
        "\(accountID).\(uid)"
    }

    private func scheduledAttemptKey(accountID: String, uid: String, serverDay: String) -> String {
        "\(accountID).\(uid).\(serverDay)"
    }
}

private final class MockAccountTokenRefreshStore: AccountTokenRefreshStoring {
    private var refreshDates: [String: Date] = [:]

    func lastRefreshDate(accountID: String) -> Date? {
        refreshDates[accountID]
    }

    func setLastRefreshDate(_ date: Date, accountID: String) {
        refreshDates[accountID] = date
    }
}

private struct MockSecretStore: AccountSecretStoring {
    var secretsByAccountID: [String: AccountSecrets] = [:]
    var deleteError: Error?

    func load(accountID: String) throws -> AccountSecrets? {
        secretsByAccountID[accountID]
    }

    func save(_ secrets: AccountSecrets, accountID: String) throws {}

    func delete(accountID: String) throws {
        if let deleteError { throw deleteError }
    }
}
