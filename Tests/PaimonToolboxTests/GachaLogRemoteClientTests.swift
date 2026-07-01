import XCTest
@testable import PaimonToolbox

final class GachaLogRemoteClientTests: XCTestCase {
    override func tearDown() {
        GachaCapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testLoadRecordsGeneratesAuthKeyAndFetchesGachaLog() async throws {
        var requests: [URLRequest] = []
        GachaCapturingURLProtocol.requestHandler = { request in
            requests.append(request)
            if request.url?.path == "/binding/api/genAuthKey" {
                let body = #"{"retcode":0,"message":"OK","data":{"authkey":"auth+key/value="}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }

            let body = """
            {
              "retcode": 0,
              "message": "OK",
              "data": {
                "list": [
                  {
                    "id": "1001",
                    "time": "2026-06-24 12:01:00",
                    "name": "莉奈娅",
                    "item_type": "角色",
                    "rank_type": "5",
                    "gacha_type": "301"
                  }
                ]
              }
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GachaLogRemoteClient(httpClient: HoYoHTTPClient(session: Self.capturingSession()))
        let records = try await client.loadRecords(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "cookie-token", ltoken: nil),
            bannerTypes: ["301"],
            pageSize: 20,
            maxPagesPerBanner: 1
        )

        XCTAssertEqual(records, [
            GachaRecord(
                id: "1001",
                time: Self.uigfDate("2026-06-24 12:01:00"),
                banner: .character,
                name: "莉奈娅",
                itemType: "角色",
                rarity: 5
            )
        ])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api-takumi.mihoyo.com/binding/api/genAuthKey")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), "stuid=10001;stoken=stoken-value;mid=mid-value")
        let authBody = try JSONSerialization.jsonObject(with: Self.bodyData(from: requests[0])) as? [String: String]
        XCTAssertEqual(authBody?["auth_appid"], "webview_gacha")
        XCTAssertEqual(authBody?["game_biz"], "hk4e_cn")
        XCTAssertEqual(authBody?["game_uid"], "100000001")
        XCTAssertEqual(authBody?["region"], "cn_gf01")
        XCTAssertEqual(requests[1].url?.host, "public-operation-hk4e.mihoyo.com")
        let gachaQuery = requests[1].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery }
        XCTAssertEqual(gachaQuery?.contains("authkey=auth%2Bkey/value%3D"), true)
        XCTAssertEqual(gachaQuery?.contains("authkey=auth+key"), false)
        XCTAssertEqual(requests[1].url?.query(percentEncoded: false)?.contains("gacha_type=301"), true)
    }

    func testLoadRecordsRetriesWhenGachaLogIsRateLimited() async throws {
        var gachaRequestCount = 0
        let sleepRecorder = SleepRecorder()
        GachaCapturingURLProtocol.requestHandler = { request in
            if request.url?.path == "/binding/api/genAuthKey" {
                let body = #"{"retcode":0,"message":"OK","data":{"authkey":"auth+key/value="}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }

            gachaRequestCount += 1
            if gachaRequestCount == 1 {
                let body = #"{"retcode":-100,"message":"visit too frequently","data":null}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }

            let body = """
            {
              "retcode": 0,
              "message": "OK",
              "data": {
                "list": [
                  {
                    "id": "1002",
                    "time": "2026-06-24 12:02:00",
                    "name": "斫峰之刃",
                    "item_type": "武器",
                    "rank_type": "5",
                    "gacha_type": "302"
                  }
                ]
              }
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GachaLogRemoteClient(
            httpClient: HoYoHTTPClient(session: Self.capturingSession()),
            pageDelayNanoseconds: 0,
            rateLimitRetryDelaysNanoseconds: [1],
            sleep: { nanoseconds in
                await sleepRecorder.append(nanoseconds)
            }
        )

        let records = try await client.loadRecords(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "cookie-token", ltoken: nil),
            bannerTypes: ["302"],
            pageSize: 20,
            maxPagesPerBanner: 1
        )

        XCTAssertEqual(gachaRequestCount, 2)
        let recordedSleeps = await sleepRecorder.calls
        XCTAssertEqual(recordedSleeps, [1])
        XCTAssertEqual(records.first?.name, "斫峰之刃")
    }

    func testLoadRecordsRequestsAllSupportedBannerTypesByDefault() async throws {
        var requestedBannerTypes: [String] = []
        GachaCapturingURLProtocol.requestHandler = { request in
            if request.url?.path == "/binding/api/genAuthKey" {
                let body = #"{"retcode":0,"message":"OK","data":{"authkey":"auth-key"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            requestedBannerTypes.append(components?.queryItems?.first { $0.name == "gacha_type" }?.value ?? "")
            let body = #"{"retcode":0,"message":"OK","data":{"list":[]}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GachaLogRemoteClient(
            httpClient: HoYoHTTPClient(session: Self.capturingSession()),
            pageDelayNanoseconds: 0
        )

        _ = try await client.loadRecords(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "cookie-token", ltoken: nil),
            pageSize: 20,
            maxPagesPerBanner: 1
        )

        XCTAssertEqual(requestedBannerTypes, ["301", "400", "302", "500", "200"])
    }

    func testLoadRecordsPreservesCharacterEventTwoAndChronicledBannerTypes() async throws {
        GachaCapturingURLProtocol.requestHandler = { request in
            if request.url?.path == "/binding/api/genAuthKey" {
                let body = #"{"retcode":0,"message":"OK","data":{"authkey":"auth-key"}}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let gachaType = components?.queryItems?.first { $0.name == "gacha_type" }?.value
            let itemName = gachaType == "500" ? "晨风之诗" : "浪涌之瞬"
            let body = """
            {
              "retcode": 0,
              "message": "OK",
              "data": {
                "list": [
                  {
                    "id": "\(gachaType ?? "")-1",
                    "time": "2026-06-24 12:03:00",
                    "name": "\(itemName)",
                    "item_type": "角色",
                    "rank_type": "5",
                    "gacha_type": "\(gachaType ?? "")"
                  }
                ]
              }
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = GachaLogRemoteClient(
            httpClient: HoYoHTTPClient(session: Self.capturingSession()),
            pageDelayNanoseconds: 0
        )

        let records = try await client.loadRecords(
            role: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            secrets: AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: "cookie-token", ltoken: nil),
            bannerTypes: ["400", "500"],
            pageSize: 20,
            maxPagesPerBanner: 1
        )

        XCTAssertEqual(records.map(\.banner.rawValue), ["characterEvent2", "chronicled"])
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GachaCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func uigfDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private actor SleepRecorder {
    private var values: [UInt64] = []

    var calls: [UInt64] {
        values
    }

    func append(_ value: UInt64) {
        values.append(value)
    }
}

private final class GachaCapturingURLProtocol: URLProtocol {
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
