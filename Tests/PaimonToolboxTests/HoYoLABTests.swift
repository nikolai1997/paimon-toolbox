import XCTest
@testable import PaimonToolbox

final class HoYoLABTests: XCTestCase {
    private static let header = "ltuid_v2=10001; ltoken_v2=example-token==; ltmid_v2=example-mid; account_id_v2=10001; cookie_token_v2=example-cookie; account_mid_v2=example-mid"
    private static var secrets: AccountSecrets { try! HoYoLABCredentials(cookieHeader: header).secrets }
    private static let role = GenshinRole(uid: "800000001", region: "os_asia", nickname: "Traveler", level: 60, isSelected: true)
    private static let roles = #"{"retcode":0,"message":"OK","data":{"list":[{"game_biz":"hk4e_global","game_uid":"600000001","region":"os_usa","nickname":"America","level":50},{"game_biz":"hk4e_global","game_uid":"800000001","region":"os_asia","nickname":"Traveler","level":60},{"game_biz":"hk4e_cn","game_uid":"100000001","region":"cn_gf01","nickname":"CN","level":60}]}}"#
    private static let note = #"{"retcode":0,"message":"OK","data":{"current_resin":120,"max_resin":200,"resin_recovery_time":"3600","finished_task_num":2,"total_task_num":4,"expeditions":[{"status":"Finished"}],"max_expedition_num":5}}"#
    private static let home = #"{"retcode":0,"message":"OK","data":{"month":11,"awards":[{"name":"Primogem","cnt":20}]}}"#
    private static let info = #"{"retcode":0,"message":"OK","data":{"total_sign_day":2,"today":"2026-11-09","is_sign":true}}"#

    override func tearDown() {
        HoYoLABURLProtocol.handler = nil
        super.tearDown()
    }

    func testCookieImportPreservesVersionsAndDropsUnrelatedCookies() throws {
        let credentials = try HoYoLABCredentials(cookieHeader: "Cookie: \(Self.header); analytics=ignored; stoken=ignored")
        XCTAssertEqual(credentials.accountID, "10001")
        XCTAssertEqual(credentials.cookies["ltoken_v2"], "example-token==")
        XCTAssertNil(credentials.cookies["ltoken"])
        XCTAssertNil(credentials.cookies["stoken"])
        XCTAssertNil(credentials.cookies["analytics"])
        XCTAssertTrue(credentials.secrets.isHoYoLAB)
        XCTAssertTrue(credentials.secrets.stoken.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(AccountSecrets.self, from: JSONEncoder().encode(credentials.secrets)), credentials.secrets)
    }

    func testLegacyCookiesRemainUsableAndDoNotBecomeV2Cookies() throws {
        let credentials = try HoYoLABCredentials(cookieHeader: "ltuid=10001; ltoken=legacy")
        XCTAssertEqual(credentials.cookies, ["ltuid": "10001", "ltoken": "legacy"])
        let data = Data(#"{"stuid":"1","stoken":"cn-token","mid":"mid","cookieToken":"cn-cookie"}"#.utf8)
        let oldSecrets = try JSONDecoder().decode(AccountSecrets.self, from: data)
        XCTAssertFalse(oldSecrets.isHoYoLAB)
        XCTAssertEqual(HoYoRequestSigner.cookieHeader(for: oldSecrets, kind: .cookieToken), "account_id=1;cookie_token=cn-cookie")
    }

    func testCookieImportRejectsMissingCredentialsConflictingAccountsAndHeaderInjection() {
        for header in ["", "ltoken_v2=token", "ltuid_v2=1", "ltuid_v2=abc; ltoken_v2=token",
                       "ltuid_v2=1; ltoken_v2=token; account_id_v2=2; cookie_token_v2=cookie",
                       "ltuid_v2=1; ltoken_v2=a; ltoken_v2=b", "ltuid_v2=1; ltoken_v2=token\r\nInjected: value"] {
            XCTAssertThrowsError(try HoYoLABCredentials(cookieHeader: header))
        }
    }

    func testCredentialsCannotBeSentToUntrustedOrCNEndpoints() throws {
        for url in ["http://sg-public-api.hoyolab.com/", "https://hoyolab.com.evil.example/",
                    "https://api-takumi.mihoyo.com/binding/api/getUserGameRolesByCookie"] {
            XCTAssertThrowsError(try HoYoLABAPI.request(url: URL(string: url)!, secrets: Self.secrets))
        }
        var cnRole = Self.role
        cnRole.region = "cn_gf01"
        XCTAssertThrowsError(try HoYoLABAPI.validate(role: cnRole, secrets: Self.secrets))
    }

    func testBrowserCookieFilterRejectsOtherDomainsAndInsecureCookies() throws {
        func cookie(_ domain: String, secure: Bool = true) throws -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain, .path: "/", .name: "ltoken_v2", .value: "token"
            ]
            if secure { properties[.secure] = "TRUE" }
            return try XCTUnwrap(HTTPCookie(properties: properties))
        }
        XCTAssertTrue(HoYoLABLoginBrowser.isAccountCookie(try cookie(".hoyolab.com")))
        XCTAssertTrue(HoYoLABLoginBrowser.isAccountCookie(try cookie("www.hoyolab.com")))
        XCTAssertFalse(HoYoLABLoginBrowser.isAccountCookie(try cookie("hoyolab.com.evil.example")))
        XCTAssertFalse(HoYoLABLoginBrowser.isAccountCookie(try cookie(".mihoyo.com")))
        XCTAssertFalse(HoYoLABLoginBrowser.isAccountCookie(try cookie(".hoyolab.com", secure: false)))
    }

    func testBindingUsesInternationalEndpointAndFiltersOtherGamesAndCN() async throws {
        var captured: URLRequest?
        HoYoLABURLProtocol.handler = { request in captured = request; return Self.roles }
        let roles = try await MiHoYoBindingClient(httpClient: Self.httpClient()).loadGenshinRoles(secrets: Self.secrets)
        XCTAssertEqual(roles.map(\.region), ["os_usa", "os_asia"])
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.host, "api-os-takumi.mihoyo.com")
        XCTAssertEqual(Self.query(request)["game_biz"], "hk4e_global")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-rpc-app_version"), "1.5.0")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "DS"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), HoYoLABCredentials.header(for: Self.secrets.hoyolabCookies!))
    }

    @MainActor
    func testLoginSelectsAsiaPersistsNamespacedAccountAndLoadsNotesWithoutCNFingerprint() async throws {
        var requests: [URLRequest] = []
        HoYoLABURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("getUserGameRolesByCookie") == true { return Self.roles }
            if request.url?.path.hasSuffix("/home") == true { return Self.home }
            if request.url?.path.hasSuffix("/info") == true { return Self.info }
            return Self.note
        }
        let metadata = HoYoLABMetadataStore()
        let secrets = HoYoLABSecretStore()
        let service = Self.service(metadata: metadata, secrets: secrets)
        let status = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .asia)
        XCTAssertEqual(status.selectedRole, Self.role)
        XCTAssertEqual(status.accountID, "hoyolab:10001")
        XCTAssertEqual(service.loadStatus(), status)
        XCTAssertNotNil(secrets.values["hoyolab:10001"]?.hoyolabCookies)

        let note = try await service.loadDeskDailyNote()
        XCTAssertEqual(note.resin, 120)
        XCTAssertEqual(note.expeditionFinished, 1)
        XCTAssertEqual(requests.count, 4)
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.url?.host, "sg-public-api.hoyolab.com")
        XCTAssertEqual(request.url?.path, "/event/game_record/genshin/api/dailyNote")
        XCTAssertEqual(Self.query(request)["server"], "os_asia")
        XCTAssertEqual(Self.query(request)["role_id"], "800000001")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-rpc-device_fp"))
        _ = try service.signOut()
        XCTAssertTrue(secrets.values.isEmpty)
        XCTAssertNil(metadata.value)
    }

    @MainActor
    func testMissingServerLeavesExistingAccountUntouched() async throws {
        HoYoLABURLProtocol.handler = { _ in Self.roles }
        let previous = AccountMetadata(account: MiHoYoAccount(accountID: "cn", mid: "cn-mid"), selectedRole: nil, lastSummary: nil)
        let metadata = HoYoLABMetadataStore(value: previous)
        let secrets = HoYoLABSecretStore()
        let service = Self.service(metadata: metadata, secrets: secrets)
        do {
            _ = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .europe)
            XCTFail("Expected missing server")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Europe"))
        }
        XCTAssertEqual(metadata.value, previous)
        XCTAssertTrue(secrets.values.isEmpty)
    }

    @MainActor
    func testCheckInOutageDoesNotBlockLoginAndMetadataFailureRestoresPreviousSecrets() async throws {
        HoYoLABURLProtocol.handler = { request in
            request.url?.path.hasSuffix("getUserGameRolesByCookie") == true
                ? Self.roles : #"{"retcode":-1,"message":"Unavailable","data":null}"#
        }
        let metadata = HoYoLABMetadataStore()
        let secrets = HoYoLABSecretStore()
        let service = Self.service(metadata: metadata, secrets: secrets)
        let status = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .asia)
        XCTAssertTrue(status.isSignedIn)
        XCTAssertNil(status.signInSummary)
        let previous = secrets.values
        metadata.failSave = true
        do {
            _ = try await service.completeHoYoLABLogin(cookieHeader: "ltuid_v2=10001; ltoken_v2=replacement", server: .asia)
            XCTFail("Expected metadata failure")
        } catch {}
        XCTAssertEqual(secrets.values, previous)
    }

    func testCheckInUsesInternationalActivityAndNestedRiskIsNeverReportedAsSuccess() async throws {
        var requests: [URLRequest] = []
        HoYoLABURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("/home") == true { return Self.home }
            if request.url?.path.hasSuffix("/info") == true { return Self.info }
            return #"{"retcode":0,"message":"OK","data":{"code":"ok","gt_result":{"risk_code":5003,"success":1,"gt":"gt","challenge":"challenge"}}}"#
        }
        let client = GenshinSignInClient(httpClient: Self.httpClient())
        let summary = try await client.loadSummary(role: Self.role, secrets: Self.secrets)
        XCTAssertTrue(summary.isTodaySigned)
        let result = try await client.claim(role: Self.role, secrets: Self.secrets)
        XCTAssertThrowsError(try LocalAccountSessionService.validateClaimResult(result))
        XCTAssertEqual(result.challenge, "challenge")
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request.url?.host, "sg-hk4e-api.hoyolab.com")
            XCTAssertEqual(Self.query(request)["act_id"], "e202102251931481")
            XCTAssertFalse((request.value(forHTTPHeaderField: "Cookie") ?? "").contains("stoken="))
        }
        XCTAssertEqual(requests[2].httpMethod, "POST")
    }

    @MainActor
    func testEmptySuccessfulClaimIsConfirmedByReadingServerStatus() async throws {
        var infoCount = 0
        HoYoLABURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("getUserGameRolesByCookie") == true { return Self.roles }
            if request.url?.path.hasSuffix("/home") == true { return Self.home }
            if request.url?.path.hasSuffix("/info") == true { infoCount += 1; return Self.info }
            return #"{"retcode":0,"message":"OK","data":{}}"#
        }
        let service = Self.service(metadata: HoYoLABMetadataStore(), secrets: HoYoLABSecretStore())
        _ = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .asia)
        let status = try await service.claimDailyReward()
        XCTAssertEqual(status.signInSummary?.isTodaySigned, true)
        XCTAssertEqual(infoCount, 2)
    }

    func testDailyNoteVerificationDoesNotFallBackToCNVerificationEndpoints() async throws {
        var requests: [URLRequest] = []
        HoYoLABURLProtocol.handler = { request in
            requests.append(request)
            return #"{"retcode":1034,"message":"Verification required","data":null}"#
        }
        do {
            _ = try await GenshinDailyNoteClient(httpClient: Self.httpClient()).load(role: Self.role, secrets: Self.secrets)
            XCTFail("Expected verification")
        } catch AccountSessionError.requiresVerification(let payload) {
            XCTAssertEqual(payload.riskCode, 1034)
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.host, "sg-public-api.hoyolab.com")
    }

    @MainActor
    func testSuccessfulClaimWithoutConfirmedSignInStatusIsRejected() async throws {
        HoYoLABURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("getUserGameRolesByCookie") == true { return Self.roles }
            if request.url?.path.hasSuffix("/home") == true { return Self.home }
            if request.url?.path.hasSuffix("/info") == true {
                return Self.info.replacingOccurrences(of: "\"is_sign\":true", with: "\"is_sign\":false")
            }
            return #"{"retcode":0,"message":"OK","data":{}}"#
        }
        let service = Self.service(metadata: HoYoLABMetadataStore(), secrets: HoYoLABSecretStore())
        _ = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .asia)
        do {
            _ = try await service.claimDailyReward()
            XCTFail("Expected unconfirmed claim to fail")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .invalidResponse("签到状态未确认成功"))
        }
    }

    @MainActor
    func testSessionRefreshNeverUsesCNTokenOrProfileEndpointsAndResignFailsLocally() async throws {
        var requests: [URLRequest] = []
        HoYoLABURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("getUserGameRolesByCookie") == true { return Self.roles }
            if request.url?.path.hasSuffix("/home") == true { return Self.home }
            return Self.info
        }
        let service = Self.service(metadata: HoYoLABMetadataStore(), secrets: HoYoLABSecretStore())
        _ = try await service.completeHoYoLABLogin(cookieHeader: Self.header, server: .asia)
        _ = try await service.refreshLoginTokens()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.dropFirst().map { $0.url?.host }, Array(repeating: "sg-hk4e-api.hoyolab.com", count: 4))
        XCTAssertThrowsError(try service.signInWebVerificationContext())
        do {
            _ = try await service.loadResignInfo()
            XCTFail("Expected unsupported CN feature")
        } catch {}
        XCTAssertEqual(requests.count, 5)
    }

    func testExpiredInternationalCookiePreservesRetcode() async throws {
        HoYoLABURLProtocol.handler = { _ in #"{"retcode":-100,"message":"Please log in","data":null}"# }
        do {
            _ = try await MiHoYoBindingClient(httpClient: Self.httpClient()).loadGenshinRoles(secrets: Self.secrets)
            XCTFail("Expected expired session")
        } catch let error as AccountSessionError {
            XCTAssertTrue(error.indicatesExpiredSession)
        }
    }

    func testWishSyncUsesCookieTokenAuthKeyAndInternationalHostForEveryServer() async throws {
        for server in HoYoLABServer.allCases {
            var requests: [URLRequest] = []
            HoYoLABURLProtocol.handler = { request in
                requests.append(request)
                if request.url?.path.hasSuffix("genAuthKeyByCookieToken") == true {
                    return #"{"retcode":0,"message":"OK","data":{"authkey":"auth%2Bkey%2Fvalue%3D"}}"#
                }
                return #"{"retcode":0,"message":"OK","data":{"list":[{"id":"123","time":"2026-11-09 12:00:00","name":"Test","item_type":"武器","rank_type":"3","gacha_type":"200"}]}}"#
            }
            var role = Self.role
            role.region = server.rawValue
            let client = GachaLogRemoteClient(httpClient: Self.httpClient(), pageDelayNanoseconds: 0)
            let records = try await client.loadRecords(role: role, secrets: Self.secrets, bannerTypes: ["200"], maxPagesPerBanner: 1)
            XCTAssertEqual(requests[0].url?.host, "api-account-os.hoyoverse.com")
            XCTAssertEqual(requests[1].url?.host, "public-operation-hk4e-sg.hoyoverse.com")
            XCTAssertEqual(Self.query(requests[1])["game_biz"], "hk4e_global")
            XCTAssertEqual(Self.query(requests[1])["region"], server.rawValue)
            XCTAssertEqual(Self.query(requests[1])["authkey"], "auth+key/value=")
            XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(records.first?.uid, role.uid)
            let date = try XCTUnwrap(records.first?.time)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            XCTAssertEqual(calendar.component(.hour, from: date), 12 - server.timeZoneHours)
        }
    }

    func testWishSyncWithoutCookieTokenFailsLocally() async throws {
        let secrets = try HoYoLABCredentials(cookieHeader: "ltuid_v2=10001; ltoken_v2=token").secrets
        HoYoLABURLProtocol.handler = { _ in XCTFail("Should not send a request"); return "" }
        do {
            _ = try await GachaLogRemoteClient(httpClient: Self.httpClient()).loadRecords(role: Self.role, secrets: secrets)
            XCTFail("Expected missing cookie token")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("cookie_token_v2"))
        }
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
    }

    private static func httpClient() -> HoYoHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HoYoLABURLProtocol.self]
        return HoYoHTTPClient(session: URLSession(configuration: configuration))
    }

    @MainActor
    private static func service(metadata: HoYoLABMetadataStore, secrets: HoYoLABSecretStore) -> LocalAccountSessionService {
        LocalAccountSessionService(metadataStore: metadata, secretStore: secrets,
            bindingClient: MiHoYoBindingClient(httpClient: httpClient()),
            signInClient: GenshinSignInClient(httpClient: httpClient()),
            dailyNoteClient: GenshinDailyNoteClient(httpClient: httpClient()))
    }
}

private final class HoYoLABMetadataStore: AccountMetadataStoring {
    var value: AccountMetadata?
    var failSave = false
    init(value: AccountMetadata? = nil) { self.value = value }
    func load() throws -> AccountMetadata? { value }
    func save(_ metadata: AccountMetadata) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        value = metadata
    }
    func clear() throws { value = nil }
}

private final class HoYoLABSecretStore: AccountSecretStoring {
    var values: [String: AccountSecrets] = [:]
    func load(accountID: String) throws -> AccountSecrets? { values[accountID] }
    func save(_ secrets: AccountSecrets, accountID: String) throws { values[accountID] = secrets }
    func delete(accountID: String) throws { values.removeValue(forKey: accountID) }
}

private final class HoYoLABURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let body = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
