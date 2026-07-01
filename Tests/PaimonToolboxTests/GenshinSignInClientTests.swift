import XCTest
@testable import PaimonToolbox

final class GenshinSignInClientTests: XCTestCase {
    override func tearDown() {
        SignInCapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testUsesCurrentLunaActivityId() {
        XCTAssertEqual(HoYoConstants.lunaActivityID, "e202311201442471")
    }

    func testLoadSummaryUsesXRpcHeadersAndCurrentActivityId() async throws {
        let capturedRequests = expectation(description: "Captured sign-in summary requests")
        capturedRequests.expectedFulfillmentCount = 2
        var requests: [URLRequest] = []

        SignInCapturingURLProtocol.requestHandler = { request in
            requests.append(request)
            capturedRequests.fulfill()
            let path = request.url?.path() ?? ""
            let body: String
            if path.hasSuffix("/home") {
                body = #"{"retcode":0,"message":"OK","data":{"month":6,"awards":[]}}"#
            } else {
                body = #"{"retcode":0,"message":"OK","data":{"total_sign_day":7,"today":"2026-06-24","is_sign":true}}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GenshinSignInClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let secrets = AccountSecrets(stuid: "10001", stoken: "token", mid: "mid", cookieToken: "cookie-token", ltoken: nil)

        _ = try await client.loadSummary(role: role, secrets: secrets)
        await fulfillment(of: [capturedRequests], timeout: 1)

        XCTAssertEqual(requests.map { $0.url?.query(percentEncoded: false) }.compactMap(\.self).filter { $0.contains("act_id=e202311201442471") }.count, 2)
        for request in requests {
            let headers = request.allHTTPHeaderFields ?? [:]
            XCTAssertEqual(headers["x-rpc-app_version"], HoYoConstants.cnAppVersion)
            XCTAssertEqual(headers["x-rpc-client_type"], "5")
            XCTAssertEqual(headers["Accept"], "application/json")
            XCTAssertEqual(headers["User-Agent"], HoYoConstants.userAgent)
            XCTAssertNotNil(headers["x-rpc-device_id"])
            XCTAssertEqual(headers["x-rpc-signgame"], "hk4e")
            XCTAssertNotNil(headers["DS"])
        }
    }

    func testClaimUsesGeetestVerificationHeaders() async throws {
        let capturedRequest = expectation(description: "Captured verified sign-in request")
        var headers: [String: String] = [:]

        SignInCapturingURLProtocol.requestHandler = { request in
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"success":0}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GenshinSignInClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let secrets = AccountSecrets(stuid: "10001", stoken: "token", mid: "mid", cookieToken: "cookie-token", ltoken: nil)
        let verification = SignInVerificationResult(challenge: "challenge-value", validate: "validate-value")

        _ = try await client.claim(role: role, secrets: secrets, verification: verification)
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(headers["x-rpc-challenge"], "challenge-value")
        XCTAssertEqual(headers["x-rpc-validate"], "validate-value")
        XCTAssertEqual(headers["x-rpc-seccode"], "validate-value|jordan")
    }

    func testVerificationResultDecodesGeetestPayload() throws {
        let json = #"{"geetest_challenge":"challenge-value","geetest_validate":"validate-value","geetest_seccode":"validate-value|jordan"}"#.data(using: .utf8)!

        let result = try JSONDecoder().decode(SignInVerificationResult.self, from: json)

        XCTAssertEqual(result.challenge, "challenge-value")
        XCTAssertEqual(result.validate, "validate-value")
        XCTAssertEqual(result.seccode, "validate-value|jordan")
    }

    func testRewardPayloadMapsClaimedDays() {
        let payload = SignInRewardHomePayload(month: 6, awards: [
            SignInAwardPayload(name: "原石", count: 20, icon: nil),
            SignInAwardPayload(name: "摩拉", count: 3000, icon: nil)
        ])
        let rewards = payload.rewards(totalSignDay: 1)
        XCTAssertEqual(rewards[0].day, 1)
        XCTAssertTrue(rewards[0].isClaimed)
        XCTAssertFalse(rewards[1].isClaimed)
    }

    func testLoadResignInfoUsesCurrentActivityIdAndRole() async throws {
        let capturedRequest = expectation(description: "Captured resign info request")
        var requestURL: URL?
        var headers: [String: String] = [:]

        SignInCapturingURLProtocol.requestHandler = { request in
            requestURL = request.url
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"resign_cnt_daily":0,"resign_cnt_monthly":1,"resign_limit_daily":1,"resign_limit_monthly":3,"sign_cnt_missed":2,"coin_cnt":5,"coin_cost":1,"rule":"rule","signed":false,"sign_days":7,"cost":0,"month_quality_cnt":0,"quality_cnt":0}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GenshinSignInClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let secrets = AccountSecrets(stuid: "10001", stoken: "token", mid: "mid", cookieToken: "cookie-token", ltoken: nil)

        let info = try await client.loadResignInfo(role: role, secrets: secrets)
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(requestURL?.path(), "/event/luna/resign_info")
        XCTAssertTrue(requestURL?.query(percentEncoded: false)?.contains("act_id=e202311201442471") == true)
        XCTAssertTrue(requestURL?.query(percentEncoded: false)?.contains("uid=100000001") == true)
        XCTAssertTrue(requestURL?.query(percentEncoded: false)?.contains("region=cn_gf01") == true)
        XCTAssertEqual(headers["x-rpc-signgame"], "hk4e")
        XCTAssertNotNil(headers["DS"])
        XCTAssertEqual(info.signCountMissed, 2)
        XCTAssertEqual(info.coinCost, 1)
        XCTAssertTrue(info.canResign)
    }

    func testResignUsesVerificationHeadersAndResignEndpoint() async throws {
        let capturedRequest = expectation(description: "Captured verified resign request")
        var requestURL: URL?
        var headers: [String: String] = [:]

        SignInCapturingURLProtocol.requestHandler = { request in
            requestURL = request.url
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"success":0}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GenshinSignInClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let secrets = AccountSecrets(stuid: "10001", stoken: "token", mid: "mid", cookieToken: "cookie-token", ltoken: nil)
        let verification = SignInVerificationResult(challenge: "challenge-value", validate: "validate-value")

        _ = try await client.resign(role: role, secrets: secrets, verification: verification)
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(requestURL?.path(), "/event/luna/resign")
        XCTAssertEqual(headers["x-rpc-challenge"], "challenge-value")
        XCTAssertEqual(headers["x-rpc-validate"], "validate-value")
        XCTAssertEqual(headers["x-rpc-seccode"], "validate-value|jordan")
    }

    func testRiskResponsePreservesChallengeData() throws {
        let response = HoYoResponse(
            retcode: -5003,
            message: "OK",
            data: SignInResultPayload(success: 0, riskCode: nil, gt: "gt-value", challenge: "challenge-value")
        )

        let payload = try GenshinSignInClient.signInResult(from: response)

        XCTAssertEqual(payload.success, 0)
        XCTAssertEqual(payload.riskCode, -5003)
        XCTAssertEqual(payload.gt, "gt-value")
        XCTAssertEqual(payload.challenge, "challenge-value")
    }

    func testClaimRequiresCookieToken() async throws {
        let client = GenshinSignInClient()
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let secrets = AccountSecrets(stuid: "1", stoken: "token", mid: "mid", cookieToken: "", ltoken: nil)

        do {
            _ = try await client.claim(role: role, secrets: secrets)
            XCTFail("Expected missingAccount error")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .missingAccount)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SignInCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class SignInCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
