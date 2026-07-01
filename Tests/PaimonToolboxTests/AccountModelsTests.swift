import XCTest
@testable import PaimonToolbox

final class AccountModelsTests: XCTestCase {
    func testQrLoginResponseDecodesTicketAndURL() throws {
        let json = #"{"retcode":0,"message":"OK","data":{"url":"https://example.com/qr","ticket":"ticket-1"}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HoYoResponse<QrLoginSession>.self, from: json)
        XCTAssertEqual(response.retcode, 0)
        XCTAssertEqual(response.data?.qrURL.absoluteString, "https://example.com/qr")
        XCTAssertEqual(response.data?.ticket, "ticket-1")
    }

    func testQrLoginStatusDecodesCreatedStateWithNullUserInfo() throws {
        let json = #"{"retcode":0,"message":"OK","data":{"status":"Created","app_id":"ddxf5dufpuyo","client_type":3,"created_at":"1782309928","scanned_at":"0","tokens":[],"user_info":null,"realname_info":null,"need_realperson":false,"ext":"","scan_game_biz":""}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(HoYoResponse<QrLoginResultPayload>.self, from: json)

        XCTAssertEqual(response.data?.pollingState, .waiting)
        XCTAssertThrowsError(try response.data?.accountSecrets()) { error in
            guard case AccountSessionError.qrLoginPending(.waiting) = error else {
                return XCTFail("Expected waiting state, got \(error)")
            }
        }
    }

    func testSignInInfoMapsSignedState() throws {
        let json = #"{"retcode":0,"message":"OK","data":{"total_sign_day":7,"today":"2026-06-24","is_sign":true}}"#.data(using: .utf8)!
        let response = try JSONDecoder().decode(HoYoResponse<SignInInfoPayload>.self, from: json)
        XCTAssertEqual(response.data?.totalSignDay, 7)
        XCTAssertTrue(response.data?.isSign == true)
    }

    func testSignInResultDecodesRiskState() throws {
        let json = #"{"retcode":0,"message":"OK","data":{"code":"risk","success":1,"risk_code":0,"is_risk":true}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(HoYoResponse<SignInResultPayload>.self, from: json)

        XCTAssertEqual(response.data?.code, "risk")
        XCTAssertEqual(response.data?.success, 1)
        XCTAssertTrue(response.data?.isRisk == true)
    }

    func testSignInWebVerificationContextProvidesMiHoYoCookies() {
        let context = SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: "10001",
            mid: "mid-10001",
            nickname: "旅行者",
            cookieToken: "cookie-token",
            ltoken: "ltoken",
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        )

        XCTAssertEqual(
            context.cookies,
            [
                AccountWebCookie(name: "account_id", value: "10001"),
                AccountWebCookie(name: "account_id_v2", value: "10001"),
                AccountWebCookie(name: "cookie_token", value: "cookie-token"),
                AccountWebCookie(name: "cookie_token_v2", value: "cookie-token"),
                AccountWebCookie(name: "ltmid", value: "mid-10001"),
                AccountWebCookie(name: "ltmid_v2", value: "mid-10001"),
                AccountWebCookie(name: "ltuid", value: "10001"),
                AccountWebCookie(name: "ltuid_v2", value: "10001"),
                AccountWebCookie(name: "ltoken", value: "ltoken"),
                AccountWebCookie(name: "ltoken_v2", value: "ltoken")
            ]
        )
        XCTAssertEqual(context.cookieHeader, "account_id=10001; account_id_v2=10001; cookie_token=cookie-token; cookie_token_v2=cookie-token; ltmid=mid-10001; ltmid_v2=mid-10001; ltuid=10001; ltuid_v2=10001; ltoken=ltoken; ltoken_v2=ltoken")
    }

    func testSignInWebVerificationContextProvidesAppBridgeUserInfo() {
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        let context = SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: "10001",
            mid: "mid-10001",
            nickname: "旅行者",
            avatarURL: URL(string: "https://bbs-static.miyoushe.com/avatar/avatar123.png"),
            cookieToken: "cookie-token",
            ltoken: "ltoken",
            selectedRole: role
        )

        XCTAssertEqual(context.userInfo["id"] as? String, "10001")
        XCTAssertEqual(context.userInfo["uid"] as? String, "10001")
        XCTAssertEqual(context.userInfo["account_id"] as? String, "10001")
        XCTAssertEqual(context.userInfo["mid"] as? String, "mid-10001")
        XCTAssertEqual(context.userInfo["nickname"] as? String, "旅行者")
        XCTAssertEqual(context.userInfo["avatar_url"] as? String, "https://bbs-static.miyoushe.com/avatar/avatar123.png")
        XCTAssertEqual(context.selectedGameRole?["game_uid"] as? String, "100000001")
        XCTAssertEqual(context.selectedGameRole?["gameUid"] as? String, "100000001")
        XCTAssertEqual(context.selectedGameRole?["game_biz"] as? String, "hk4e_cn")
        XCTAssertEqual(context.selectedGameRole?["gameBiz"] as? String, "hk4e_cn")
        XCTAssertEqual(context.selectedGameRole?["region"] as? String, "cn_gf01")
        XCTAssertEqual(context.selectedGameRole?["region_name"] as? String, "cn_gf01")
        XCTAssertEqual(context.selectedGameRole?["nickname"] as? String, "空")
        XCTAssertEqual(context.selectedGameRole?["level"] as? Int, 60)
        XCTAssertEqual(context.selectedGameRole?["is_official"] as? Bool, true)
    }

    func testUserFullInfoDecodesPreferredAvatarURL() throws {
        let json = #"{"retcode":0,"message":"OK","data":{"user_info":{"uid":"10001","nickname":"派蒙","avatar":"123","avatar_url":"https://bbs-static.miyoushe.com/avatar/custom.png","avatar_ext":{"avatar_type":"png","hd_resources":[{"format":"png","url":"https://bbs-static.miyoushe.com/avatar/hd.png"}]}}}}"#.data(using: .utf8)!

        let response = try JSONDecoder().decode(HoYoResponse<MiHoYoUserFullInfoPayload>.self, from: json)

        XCTAssertEqual(response.data?.userInfo.nickname, "派蒙")
        XCTAssertEqual(response.data?.userInfo.resolvedAvatarURL?.absoluteString, "https://bbs-static.miyoushe.com/avatar/hd.png")
    }
}
