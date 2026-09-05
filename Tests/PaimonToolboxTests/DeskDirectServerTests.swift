import XCTest
@testable import PaimonToolbox

final class DeskDirectServerTests: XCTestCase {
    func testHTTPParserWaitsForDeclaredBodyAndPreservesJSONBytes() throws {
        let body = Data(#"{"action":"refresh"}"#.utf8)
        let complete = Self.request(method: "POST", target: "/v1/device/actions", body: body)
        let partial = complete.dropLast(4)

        XCTAssertThrowsError(try DeskHTTPRequestParser.parse(Data(partial))) { error in
            XCTAssertEqual(error as? DeskHTTPRequestParseError, .incomplete)
        }

        let parsed = try DeskHTTPRequestParser.parse(complete)
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.target, "/v1/device/actions")
        XCTAssertEqual(parsed.body, body)
    }

    func testHTTPParserRejectsAmbiguousFraming() {
        let duplicateLength = Data("GET /health HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n".utf8)
        let chunked = Data("POST /v1/device/actions HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)

        for request in [duplicateLength, chunked] {
            XCTAssertThrowsError(try DeskHTTPRequestParser.parse(request)) { error in
                XCTAssertEqual(error as? DeskHTTPRequestParseError, .invalid)
            }
        }
    }

    @MainActor
    func testTokenRequiresCurrentAccountBoundHostAndUnexpiredGrant() async throws {
        var currentTime = Date(timeIntervalSince1970: 1_788_479_000)
        var accountID = "account-a"
        let server = DeskDirectServer(persistenceURL: nil, now: { currentTime })
        server.accountIDProvider = { accountID }
        server.snapshotProvider = { Data(#"{"status":"ready"}"#.utf8) }
        let token = server.issueAccessToken(
            for: DirectDeskDevice(deviceID: "desk-1", name: "Desk", status: "available", host: "192.168.1.8"),
            accountID: accountID
        )
        let request = Self.request(
            method: "GET",
            target: "/v1/device/state",
            headers: ["Authorization": "Bearer \(token)"]
        )

        let allowed = await server.handleHTTP(data: request, remoteHost: "192.168.1.8")
        let wrongHost = await server.handleHTTP(data: request, remoteHost: "192.168.1.9")
        XCTAssertEqual(Self.statusCode(allowed), 200)
        XCTAssertEqual(Self.statusCode(wrongHost), 401)

        accountID = "account-b"
        let wrongAccount = await server.handleHTTP(data: request, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(wrongAccount), 401)

        accountID = "account-a"
        currentTime = currentTime.addingTimeInterval(DeskDirectServer.tokenLifetime)
        let expired = await server.handleHTTP(data: request, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(expired), 401)
    }

    @MainActor
    func testPairingRequiresExactCodeSameHostAndCanBeClaimedOnce() async throws {
        var currentTime = Date(timeIntervalSince1970: 1_788_479_000)
        let server = DeskDirectServer(persistenceURL: nil, now: { currentTime })
        server.accountIDProvider = { "account-a" }
        var pairing: DeskDirectPairingRequest?
        server.onPairingRequest = { pairing = $0 }
        let createBody = Data(#"{"device_id":"desk-1"}"#.utf8)
        let createRequest = Self.request(method: "POST", target: "/v1/device-pairings/request", body: createBody)

        let createdResponse = await server.handleHTTP(data: createRequest, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(createdResponse), 200)
        let created = try XCTUnwrap(pairing)
        XCTAssertFalse(server.approve(requestID: created.requestID, displayCode: ""))
        XCTAssertFalse(server.approve(requestID: created.requestID, displayCode: "AAAAAAAA"))
        XCTAssertTrue(server.approve(requestID: created.requestID, displayCode: created.displayCode))

        let target = "/v1/device-pairings/\(created.requestID)?display_code=\(created.displayCode)"
        let statusRequest = Self.request(method: "GET", target: target)
        let wrongHost = await server.handleHTTP(data: statusRequest, remoteHost: "192.168.1.9")
        let firstClaim = await server.handleHTTP(data: statusRequest, remoteHost: "192.168.1.8")
        let repeatedClaim = await server.handleHTTP(data: statusRequest, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(wrongHost), 404)
        XCTAssertEqual(Self.statusCode(firstClaim), 200)
        XCTAssertEqual(Self.statusCode(repeatedClaim), 404)

        let expiringResponse = await server.handleHTTP(data: createRequest, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(expiringResponse), 200)
        let expiring = try XCTUnwrap(pairing)
        currentTime = currentTime.addingTimeInterval(DeskDirectServer.pairingLifetime + 1)
        XCTAssertFalse(server.approve(requestID: expiring.requestID, displayCode: expiring.displayCode))
    }

    @MainActor
    func testPairingRequestsRequireLoginAndAreRateLimitedPerHost() async {
        var accountID: String?
        let server = DeskDirectServer(persistenceURL: nil)
        server.accountIDProvider = { accountID }
        let body = Data(#"{"device_id":"desk-1"}"#.utf8)
        let request = Self.request(method: "POST", target: "/v1/device-pairings/request", body: body)

        let signedOut = await server.handleHTTP(data: request, remoteHost: "192.168.1.8")
        XCTAssertEqual(Self.statusCode(signedOut), 403)
        accountID = "account-a"
        var statuses: [Int?] = []
        for _ in 0..<4 {
            let response = await server.handleHTTP(data: request, remoteHost: "192.168.1.8")
            statuses.append(Self.statusCode(response))
        }
        XCTAssertEqual(statuses, [200, 200, 200, 429])
    }

    private static func request(
        method: String,
        target: String,
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> Data {
        var values = headers
        if !body.isEmpty { values["Content-Length"] = String(body.count) }
        var text = "\(method) \(target) HTTP/1.1\r\n"
        for (name, value) in values.sorted(by: { $0.key < $1.key }) {
            text += "\(name): \(value)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8) + body
    }

    private static func statusCode(_ response: Data) -> Int? {
        guard let firstLine = String(data: response, encoding: .utf8)?.components(separatedBy: "\r\n").first else {
            return nil
        }
        return firstLine.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }
}
