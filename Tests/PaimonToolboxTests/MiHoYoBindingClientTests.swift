import XCTest
@testable import PaimonToolbox

final class MiHoYoBindingClientTests: XCTestCase {
    func testRoleListSelectsFirstRole() throws {
        let roles = BoundRoleListPayload(list: [
            BoundRolePayload(gameBiz: "hk4e_cn", gameUid: "100000001", region: "cn_gf01", nickname: "空", level: 60)
        ])
        XCTAssertEqual(roles.genshinRoles().first?.uid, "100000001")
        XCTAssertEqual(roles.genshinRoles().first?.isSelected, true)
    }

    func testLoadGenshinRolesRequiresCookieToken() async throws {
        let client = MiHoYoBindingClient()
        let secrets = AccountSecrets(stuid: "1", stoken: "token", mid: "mid", cookieToken: nil, ltoken: nil)

        do {
            _ = try await client.loadGenshinRoles(secrets: secrets)
            XCTFail("Expected missingAccount error")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .missingAccount)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
