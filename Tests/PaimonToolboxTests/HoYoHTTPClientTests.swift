import XCTest
@testable import PaimonToolbox

final class HoYoHTTPClientTests: XCTestCase {
    override func tearDown() {
        HTTPClientCapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testNonSuccessStatusIncludesHTTPStatusAndBody() async throws {
        HTTPClientCapturingURLProtocol.requestHandler = { request in
            let body = #"{"message":"not found"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = HoYoHTTPClient(session: Self.capturingSession())

        do {
            let _: HoYoResponse<EmptyPayload> = try await client.send(URLRequest(url: URL(string: "https://example.com/test")!))
            XCTFail("Expected network failure")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .networkFailure("HTTP 404：{\"message\":\"not found\"}"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPClientCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct EmptyPayload: Decodable {}

private final class HTTPClientCapturingURLProtocol: URLProtocol {
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
