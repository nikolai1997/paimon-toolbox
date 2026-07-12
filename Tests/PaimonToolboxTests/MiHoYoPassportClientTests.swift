import XCTest
@testable import PaimonToolbox

final class MiHoYoPassportClientTests: XCTestCase {
    override func tearDown() {
        CapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCreateQrLoginUsesHoyoPlayRpcHeaders() async throws {
        let capturedRequest = expectation(description: "Captured create QR login request")
        var headers: [String: String] = [:]
        CapturingURLProtocol.requestHandler = { request in
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"url":"https://example.com/qr","ticket":"ticket-1"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        _ = try await client.createQrLogin()
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(headers["x-rpc-app_id"], "ddxf5dufpuyo")
        XCTAssertEqual(headers["x-rpc-client_type"], "3")
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertEqual(headers["User-Agent"], "HYPContainer/1.1.4.133")
        XCTAssertNotNil(headers["x-rpc-device_id"])
    }

    func testRefreshCookieTokenUsesBbsRpcHeaders() async throws {
        let capturedRequest = expectation(description: "Captured refresh cookie token request")
        var headers: [String: String] = [:]
        CapturingURLProtocol.requestHandler = { request in
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"uid":"10001","cookie_token":"cookie-token"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        _ = try await client.refreshCookieToken(
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: nil)
        )
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(headers["x-rpc-aigis"], "")
        XCTAssertEqual(headers["x-rpc-app_id"], "bll8iq97cem8")
        XCTAssertEqual(headers["x-rpc-app_version"], "2.95.1")
        XCTAssertEqual(headers["x-rpc-client_type"], "2")
        XCTAssertEqual(headers["x-rpc-device_name"], "")
        XCTAssertEqual(headers["x-rpc-game_biz"], "bbs_cn")
        XCTAssertEqual(headers["x-rpc-sdk_version"], "2.16.0")
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertEqual(headers["User-Agent"], HoYoConstants.userAgent)
    }

    func testRefreshCookieTokenRejectsEmptyValue() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let body = #"{"retcode":0,"message":"OK","data":{"uid":"10001","cookie_token":"   "}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.refreshCookieToken(
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "old-cookie", ltoken: nil)
            )
            XCTFail("Expected invalid response")
        } catch let error as AccountSessionError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testRefreshCookieTokenRejectsMismatchedUID() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let body = #"{"retcode":0,"message":"OK","data":{"uid":"20002","cookie_token":"new-cookie"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.refreshCookieToken(
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "old-cookie", ltoken: nil)
            )
            XCTFail("Expected invalid response")
        } catch let error as AccountSessionError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testRefreshLTokenUsesBbsRpcHeaders() async throws {
        let capturedRequest = expectation(description: "Captured refresh ltoken request")
        var headers: [String: String] = [:]
        CapturingURLProtocol.requestHandler = { request in
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"ltoken":"ltoken-value"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let secrets = try await client.refreshLToken(
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: nil)
        )
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(secrets.ltoken, "ltoken-value")
        XCTAssertEqual(headers["x-rpc-app_id"], "bll8iq97cem8")
        XCTAssertEqual(headers["x-rpc-client_type"], "2")
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertEqual(headers["User-Agent"], HoYoConstants.userAgent)
    }

    func testRefreshLTokenPreservesAPIRetcode() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let body = #"{"retcode":-100,"message":"session rejected","data":null}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.refreshLToken(
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: nil)
            )
            XCTFail("Expected API failure")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error.apiRetcode, -100)
            XCTAssertEqual(error.localizedDescription, "接口返回错误：session rejected")
        }
    }

    func testRefreshLTokenRejectsEmptyValue() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let body = #"{"retcode":0,"message":"OK","data":{"ltoken":"\n\t"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.refreshLToken(
                secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: "old-ltoken")
            )
            XCTFail("Expected invalid response")
        } catch let error as AccountSessionError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testLoadUserFullInfoUsesAidAndReturnsNicknameAvatarURL() async throws {
        let capturedRequest = expectation(description: "Captured user full info request")
        var capturedURL: URL?
        var headers: [String: String] = [:]
        CapturingURLProtocol.requestHandler = { request in
            capturedURL = request.url
            headers = request.allHTTPHeaderFields ?? [:]
            capturedRequest.fulfill()
            let body = #"{"retcode":0,"message":"OK","data":{"user_info":{"uid":"10001","nickname":"派蒙","avatar":"123","avatar_url":"https://bbs-static.miyoushe.com/avatar/custom.png"}}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = MiHoYoUserClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let profile = try await client.loadUserProfile(accountID: "10001")
        await fulfillment(of: [capturedRequest], timeout: 1)

        XCTAssertEqual(capturedURL?.absoluteString, "https://bbs-api.mihoyo.com/user/wapi/getUserFullInfo?uid=10001&gids=2")
        XCTAssertEqual(headers["Referer"], "https://bbs.mihoyo.com/")
        XCTAssertEqual(headers["User-Agent"], HoYoConstants.userAgent)
        XCTAssertEqual(profile.nickname, "派蒙")
        XCTAssertEqual(profile.avatarURL?.absoluteString, "https://bbs-static.miyoushe.com/avatar/custom.png")
    }

    func testQueryQrLoginStatusKeepsPollingOnTransientLoginStatusError() async throws {
        CapturingURLProtocol.requestHandler = { request in
            let body = #"{"retcode":-100,"message":"登录状态失效，请重新登录","data":null}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = MiHoYoPassportClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))

        do {
            _ = try await client.queryQrLoginStatus(ticket: "ticket-1")
            XCTFail("Expected qrLoginPending error")
        } catch AccountSessionError.qrLoginPending(let state) {
            XCTAssertEqual(state, .scanned)
        } catch {
            XCTFail("Expected qrLoginPending error, got \(error)")
        }
    }

    func testConfirmedQrLoginBuildsSecrets() throws {
        let result = QrLoginResultPayload(
            status: "Confirmed",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )
        let secrets = try result.accountSecrets()
        XCTAssertEqual(secrets.stuid, "10001")
        XCTAssertEqual(secrets.stoken, "stoken-value")
        XCTAssertEqual(secrets.mid, "mid-value")
    }

    func testScannedQrLoginThrowsPendingState() {
        let result = QrLoginResultPayload(
            status: "Scanned",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )

        XCTAssertThrowsError(try result.accountSecrets()) { error in
            guard case AccountSessionError.qrLoginPending(let state) = error else {
                return XCTFail("Expected qrLoginPending error")
            }
            XCTAssertEqual(state, .scanned)
        }
    }

    func testExpiredQrLoginThrowsPendingState() {
        let result = QrLoginResultPayload(
            status: "Expired",
            tokens: [QrLoginToken(tokenType: 1, token: "stoken-value")],
            userInfo: QrLoginUserInfo(aid: "10001", mid: "mid-value", nickname: "旅行者")
        )

        XCTAssertThrowsError(try result.accountSecrets()) { error in
            guard case AccountSessionError.qrLoginPending(let state) = error else {
                return XCTFail("Expected qrLoginPending error")
            }
            XCTAssertEqual(state, .expired)
        }
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class CapturingURLProtocol: URLProtocol {
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
