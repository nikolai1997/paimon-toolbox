import XCTest
@testable import PaimonToolbox

final class GenshinDailyNoteClientTests: XCTestCase {
    override func tearDown() {
        DailyNoteCapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadsPlayerInfoBeforeDailyNoteAndUsesStableFingerprint() async throws {
        let observedAt = Date(timeIntervalSince1970: 1_788_479_000)
        var requests: [URLRequest] = []
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("/index") == true {
                return Self.response(request, body: #"{"retcode":0,"message":"OK","data":{}}"#)
            }

            let body = #"{"retcode":0,"message":"OK","data":{"current_resin":120,"max_resin":200,"resin_recovery_time":"3600","finished_task_num":2,"total_task_num":4,"expeditions":[{"status":"Finished"},{"status":"Ongoing"}],"max_expedition_num":5}}"#
            return Self.response(request, body: body)
        }

        let client = GenshinDailyNoteClient(
            httpClient: HoYoHTTPClient(session: Self.capturingSession()),
            now: { observedAt }
        )
        let note = try await client.load(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(
                stuid: "10001",
                stoken: "stoken-value",
                mid: "mid-value",
                cookieToken: "cookie-token",
                ltoken: "ltoken-value",
                deviceFingerprint: "fingerprint13"
            )
        )

        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/game_record/app/genshin/api/index",
            "/game_record/app/genshin/api/dailyNote",
        ])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-device_fp"), "fingerprint13")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-tool_verison"), "v5.0.1-ys")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-app_version"), "2.95.1")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-client_type"), "5")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-device_id"), HoYoConstants.deviceID)
        XCTAssertNotNil(UUID(uuidString: HoYoConstants.deviceID))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "User-Agent"), HoYoConstants.userAgent)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Referer"), "https://webstatic.mihoyo.com")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Referer"), "https://webstatic.mihoyo.com")
        let cookie = requests[1].value(forHTTPHeaderField: "Cookie") ?? ""
        XCTAssertEqual(cookie, "account_id=10001;cookie_token=cookie-token;ltuid=10001;ltoken=ltoken-value")
        XCTAssertFalse(cookie.contains("stoken"))
        XCTAssertFalse(cookie.contains("mid"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "x-rpc-challenge_game"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "x-rpc-tool_verison"))
        XCTAssertEqual(note.resin, 120)
        XCTAssertEqual(note.commissionDone, 2)
        XCTAssertEqual(note.expeditionFinished, 1)
        XCTAssertEqual(note.expeditionTotal, 5)
        XCTAssertEqual(note.observedAt, observedAt)
        XCTAssertEqual(note.resinRecoveryAt, observedAt.addingTimeInterval(3_600))
    }

    func testDeviceFingerprintClientUsesOfficialEndpointAndReturnsIssuedFingerprint() async throws {
        var capturedRequest: URLRequest?
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            capturedRequest = request
            return Self.response(
                request,
                body: #"{"retcode":0,"message":"OK","data":{"device_fp":"server-issued-fp","code":200,"message":"OK"}}"#
            )
        }

        let client = HoYoDeviceFingerprintClient(
            httpClient: HoYoHTTPClient(session: Self.capturingSession())
        )
        let fingerprint = try await client.fetch(existingFingerprint: "0123456789abc")

        XCTAssertEqual(fingerprint, "server-issued-fp")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://public-data-api.mihoyo.com/device-fp/api/getFp")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), HoYoConstants.userAgent)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let body = try XCTUnwrap(capturedRequest.flatMap(Self.bodyData))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["device_fp"] as? String, "0123456789abc")
        XCTAssertEqual(payload["bbs_device_id"] as? String, HoYoConstants.deviceID)
        XCTAssertEqual(payload["platform"] as? String, "2")
        XCTAssertNotNil(payload["ext_fields"] as? String)
    }

    func testAppliesVerificationChallengeToIndexAndDailyNoteRetry() async throws {
        var requests: [URLRequest] = []
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            requests.append(request)
            if request.url?.path.hasSuffix("/index") == true {
                return Self.response(request, body: #"{"retcode":0,"message":"OK","data":{}}"#)
            }
            return Self.response(
                request,
                body: #"{"retcode":0,"message":"OK","data":{"current_resin":120,"max_resin":200,"resin_recovery_time":"0","finished_task_num":2,"total_task_num":4,"expeditions":[],"max_expedition_num":5}}"#
            )
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        _ = try await client.load(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value"),
            verificationChallenge: "server-retry-challenge"
        )

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-rpc-challenge"), "server-retry-challenge")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "x-rpc-challenge"), "server-retry-challenge")
    }

    func testPreservesRetcodeForNonRiskDailyNoteFailure() async {
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/index") == true {
                return Self.response(request, body: #"{"retcode":-1,"message":"service unavailable","data":null}"#)
            }
            return Self.response(request, body: #"{"retcode":0,"message":"OK","data":{}}"#)
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.load(
                role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value")
            )
            XCTFail("Expected the non-risk API failure to be thrown")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .apiFailureResponse(retcode: -1, message: "service unavailable"))
            XCTAssertFalse(error.indicatesExpiredSession)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReportsSuccessfulResponseWithoutDataAsInvalidResponse() async {
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            Self.response(request, body: #"{"retcode":0,"message":"OK","data":null}"#)
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.load(
                role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value")
            )
            XCTFail("Expected the missing data response to be thrown")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .invalidResponse("接口成功响应缺少 data"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPositive5003FromIndexStartsVerificationFlow() async {
        var requestedPaths: [String] = []
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            requestedPaths.append(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/index") == true {
                return Self.response(request, body: #"{"retcode":5003,"message":"","data":null}"#)
            }
            return Self.response(
                request,
                body: #"{"retcode":0,"message":"OK","data":{"gt":"gt-value","challenge":"challenge-value"}}"#
            )
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.load(
                role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
                secrets: AccountSecrets(
                    stuid: "10001",
                    stoken: "stoken-value",
                    mid: "mid-value",
                    cookieToken: "cookie-token",
                    ltoken: "ltoken-value"
                )
            )
            XCTFail("Expected verification to be required")
        } catch let error as AccountSessionError {
            guard case let .requiresVerification(payload) = error else {
                return XCTFail("Expected requiresVerification, got \(error)")
            }
            XCTAssertEqual(payload.riskCode, 5003)
            XCTAssertEqual(payload.gt, "gt-value")
            XCTAssertEqual(payload.challenge, "challenge-value")
            XCTAssertEqual(payload.challengePath, "/game_record/app/genshin/api/index")
            XCTAssertEqual(requestedPaths, [
                "/game_record/app/genshin/api/index",
                "/game_record/app/card/wapi/createVerification",
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateVerificationUsesHighSecurityModeAndOriginalChallengePath() async {
        var createRequest: URLRequest?
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            if request.url?.path.hasSuffix("/index") == true {
                return Self.response(request, body: #"{"retcode":5003,"message":"","data":null}"#)
            }
            createRequest = request
            return Self.response(
                request,
                body: #"{"retcode":0,"message":"OK","data":{"gt":"gt-value","challenge":"challenge-value"}}"#
            )
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        _ = try? await client.load(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value")
        )

        XCTAssertEqual(URLComponents(url: createRequest!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "true")
        XCTAssertEqual(createRequest?.value(forHTTPHeaderField: "x-rpc-challenge_game"), "2")
        XCTAssertEqual(createRequest?.value(forHTTPHeaderField: "x-rpc-challenge_path"), "/game_record/app/genshin/api/index")
        XCTAssertEqual(createRequest?.value(forHTTPHeaderField: "x-rpc-app_version"), "2.95.1")
        XCTAssertEqual(createRequest?.value(forHTTPHeaderField: "x-rpc-client_type"), "5")
        XCTAssertEqual(createRequest?.value(forHTTPHeaderField: "User-Agent"), HoYoConstants.userAgent)
        XCTAssertNil(createRequest?.value(forHTTPHeaderField: "x-rpc-tool_verison"))
    }

    func testVerifyUsesOriginalChallengePathAndReturnsServerChallenge() async throws {
        var verificationRequest: URLRequest?
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            verificationRequest = request
            return Self.response(
                request,
                body: #"{"retcode":0,"message":"OK","data":{"challenge":"server-retry-challenge"}}"#
            )
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let retryChallenge = try await client.verify(
            SignInVerificationResult(challenge: "geetest-challenge", validate: "geetest-validate"),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value"),
            challengePath: "/game_record/app/genshin/api/index"
        )

        XCTAssertEqual(retryChallenge, "server-retry-challenge")
        XCTAssertEqual(verificationRequest?.url?.path, "/game_record/app/card/wapi/verifyVerification")
        XCTAssertEqual(verificationRequest?.value(forHTTPHeaderField: "x-rpc-challenge_game"), "2")
        XCTAssertEqual(verificationRequest?.value(forHTTPHeaderField: "x-rpc-challenge_path"), "/game_record/app/genshin/api/index")
        XCTAssertEqual(verificationRequest?.value(forHTTPHeaderField: "x-rpc-app_version"), "2.95.1")
        XCTAssertEqual(verificationRequest?.value(forHTTPHeaderField: "x-rpc-client_type"), "5")
        XCTAssertEqual(verificationRequest?.value(forHTTPHeaderField: "User-Agent"), HoYoConstants.userAgent)
        XCTAssertNil(verificationRequest?.value(forHTTPHeaderField: "x-rpc-tool_verison"))
        let body = try XCTUnwrap(verificationRequest.flatMap(Self.bodyData))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload["geetest_challenge"], "geetest-challenge")
        XCTAssertEqual(payload["geetest_validate"], "geetest-validate")
        XCTAssertEqual(payload["geetest_seccode"], "geetest-validate|jordan")
    }

    func testReportsRejectedVerificationTicketWithoutUnknownError() async {
        DailyNoteCapturingURLProtocol.requestHandler = { request in
            Self.response(request, body: #"{"retcode":10306,"message":"","data":null}"#)
        }

        let client = GenshinDailyNoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.verify(
                SignInVerificationResult(challenge: "geetest-challenge", validate: "geetest-validate"),
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value"),
                challengePath: "/game_record/app/genshin/api/index"
            )
            XCTFail("Expected the rejected ticket to fail")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .invalidResponse("安全验证票据无效，请重新打开验证"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DailyNoteCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class DailyNoteCapturingURLProtocol: URLProtocol {
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
