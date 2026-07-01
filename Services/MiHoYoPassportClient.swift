import Foundation

struct QrLoginResultPayload: Codable, Equatable {
    var status: String
    var tokens: [QrLoginToken]
    var userInfo: QrLoginUserInfo?

    enum CodingKeys: String, CodingKey {
        case status
        case tokens
        case userInfo = "user_info"
    }

    var pollingState: QrLoginPollingState {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "confirmed":
            return .confirmed
        case "scanned":
            return .scanned
        case "created", "pending", "init":
            return .waiting
        case "expired":
            return .expired
        case "canceled", "cancelled":
            return .canceled
        default:
            return .failed(status)
        }
    }

    func accountSecrets() throws -> AccountSecrets {
        let state = pollingState
        guard state == .confirmed else {
            throw AccountSessionError.qrLoginPending(state)
        }
        guard let stoken = tokens.first(where: { $0.tokenType == 1 })?.token else {
            throw AccountSessionError.invalidResponse("扫码登录结果缺少 SToken")
        }
        guard let userInfo else {
            throw AccountSessionError.invalidResponse("扫码登录结果缺少用户信息")
        }
        return AccountSecrets(stuid: userInfo.aid, stoken: stoken, mid: userInfo.mid, cookieToken: nil, ltoken: nil)
    }
}

struct QrLoginToken: Codable, Equatable {
    var tokenType: Int
    var token: String

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case token
    }
}

struct QrLoginUserInfo: Codable, Equatable {
    var aid: String
    var mid: String
    var nickname: String?
}

struct CookieTokenPayload: Codable, Equatable {
    var uid: String?
    var cookieToken: String

    enum CodingKeys: String, CodingKey {
        case uid
        case cookieToken = "cookie_token"
    }
}

struct LTokenPayload: Codable, Equatable {
    var ltoken: String
}

struct MiHoYoPassportClient {
    var httpClient = HoYoHTTPClient()

    func createQrLogin() async throws -> QrLoginSession {
        var request = URLRequest(url: URL(string: "https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin")!)
        request.httpMethod = "POST"
        request.httpBody = "{}".data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyHoyoPlayHeaders()
        let response: HoYoResponse<QrLoginSession> = try await httpClient.send(request)
        return try response.requireData()
    }

    func queryQrLoginStatus(ticket: String) async throws -> QrLoginResultPayload {
        var request = URLRequest(url: URL(string: "https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ticket": ticket])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyHoyoPlayHeaders()
        let response: HoYoResponse<QrLoginResultPayload> = try await httpClient.send(request)
        return try Self.qrLoginResult(from: response)
    }

    func refreshCookieToken(secrets: AccountSecrets) async throws -> AccountSecrets {
        let url = URL(string: "https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(HoYoRequestSigner.cookieHeader(for: secrets, kind: .stoken), forHTTPHeaderField: "Cookie")
        request.setValue(HoYoRequestSigner.dsHeader(url: url, body: nil, version: .gen2, salt: HoYoSalt.prod, includeLetters: true), forHTTPHeaderField: "DS")
        request.applyBbsHeaders()
        let response: HoYoResponse<CookieTokenPayload> = try await httpClient.send(request)
        let payload = try response.requireData()
        var updated = secrets
        updated.cookieToken = payload.cookieToken
        return updated
    }

    func refreshLToken(secrets: AccountSecrets) async throws -> AccountSecrets {
        let url = URL(string: "https://passport-api.mihoyo.com/account/auth/api/getLTokenBySToken")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(HoYoRequestSigner.cookieHeader(for: secrets, kind: .stoken), forHTTPHeaderField: "Cookie")
        request.setValue(HoYoRequestSigner.dsHeader(url: url, body: nil, version: .gen2, salt: HoYoSalt.prod, includeLetters: true), forHTTPHeaderField: "DS")
        request.applyBbsHeaders()
        let response: HoYoResponse<LTokenPayload> = try await httpClient.send(request)
        let payload = try response.requireData()
        var updated = secrets
        updated.ltoken = payload.ltoken
        return updated
    }

    private static func qrLoginResult(from response: HoYoResponse<QrLoginResultPayload>) throws -> QrLoginResultPayload {
        if response.retcode == 0, let data = response.data {
            return data
        }

        if response.retcode == -3501 {
            throw AccountSessionError.qrLoginPending(.expired)
        }

        if response.message.contains("登录状态失效") {
            throw AccountSessionError.qrLoginPending(.scanned)
        }

        throw AccountSessionError.apiFailure(response.message)
    }
}

extension HoYoResponse {
    func requireData() throws -> T {
        guard retcode == 0, let data else {
            throw AccountSessionError.apiFailure(message)
        }
        return data
    }
}

private extension URLRequest {
    mutating func applyBbsHeaders() {
        setValue("application/json", forHTTPHeaderField: "Accept")
        setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        setValue("", forHTTPHeaderField: "x-rpc-aigis")
        setValue(HoYoConstants.bbsAppID, forHTTPHeaderField: "x-rpc-app_id")
        setValue(HoYoConstants.cnAppVersion, forHTTPHeaderField: "x-rpc-app_version")
        setValue(HoYoConstants.bbsClientType, forHTTPHeaderField: "x-rpc-client_type")
        setValue(HoYoConstants.deviceID, forHTTPHeaderField: "x-rpc-device_id")
        setValue("", forHTTPHeaderField: "x-rpc-device_name")
        setValue(HoYoConstants.bbsGameBiz, forHTTPHeaderField: "x-rpc-game_biz")
        setValue(HoYoConstants.bbsSDKVersion, forHTTPHeaderField: "x-rpc-sdk_version")
    }

    mutating func applyHoyoPlayHeaders() {
        setValue("application/json", forHTTPHeaderField: "Accept")
        setValue(HoYoConstants.hoyoPlayUserAgent, forHTTPHeaderField: "User-Agent")
        setValue(HoYoConstants.hoyoPlayAppID, forHTTPHeaderField: "x-rpc-app_id")
        setValue(HoYoConstants.hoyoPlayClientType, forHTTPHeaderField: "x-rpc-client_type")
        setValue(HoYoConstants.hoyoPlayDeviceID, forHTTPHeaderField: "x-rpc-device_id")
    }
}
