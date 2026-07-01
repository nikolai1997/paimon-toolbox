import XCTest
@testable import PaimonToolbox

final class HoYoRequestSignerTests: XCTestCase {
    func testSortedQueryForGen2Signature() throws {
        let url = URL(string: "https://example.com/path?b=2&a=1")!
        XCTAssertEqual(HoYoRequestSigner.sortedQuery(for: url), "a=1&b=2")
    }

    func testCookieHeaderSkipsMissingValues() {
        let secrets = AccountSecrets(stuid: "10001", stoken: "token", mid: "mid", cookieToken: "cookie", ltoken: nil)
        XCTAssertEqual(HoYoRequestSigner.cookieHeader(for: secrets, kind: .cookieToken), "account_id=10001;cookie_token=cookie")
        XCTAssertEqual(HoYoRequestSigner.cookieHeader(for: secrets, kind: .stoken), "stuid=10001;stoken=token;mid=mid")
    }
}
