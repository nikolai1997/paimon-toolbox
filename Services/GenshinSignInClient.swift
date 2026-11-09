import Foundation

private struct HoYoLABSignInPayload: Decodable {
    var result: SignInResultPayload

    private enum CodingKeys: String, CodingKey { case gtResult = "gt_result" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let root = try SignInResultPayload(from: decoder)
        result = try container.decodeIfPresent(SignInResultPayload.self, forKey: .gtResult) ?? root
        if result.code == nil { result.code = root.code }
        if root.isRisk == true { result.isRisk = true }
        if let riskCode = root.riskCode, riskCode != 0 { result.riskCode = riskCode }
    }
}

struct SignInRewardHomePayload: Codable, Equatable {
    var month: Int
    var awards: [SignInAwardPayload]

    func rewards(totalSignDay: Int) -> [SignInReward] {
        awards.enumerated().map { index, award in
            SignInReward(
                day: index + 1,
                name: award.name,
                count: award.count,
                iconURL: award.icon.flatMap(URL.init(string:)),
                isClaimed: index < totalSignDay
            )
        }
    }
}

struct SignInAwardPayload: Codable, Equatable {
    var name: String
    var count: Int
    var icon: String?

    enum CodingKeys: String, CodingKey {
        case name
        case count = "cnt"
        case icon
    }
}

struct SignInData: Encodable {
    var actID = HoYoConstants.lunaActivityID
    var uid: String
    var region: String

    enum CodingKeys: String, CodingKey {
        case actID = "act_id"
        case uid
        case region
    }
}

struct GenshinSignInClient {
    var httpClient = HoYoHTTPClient()

    func loadSummary(role: GenshinRole, secrets: AccountSecrets) async throws -> SignInSummary {
        try HoYoLABAPI.validate(role: role, secrets: secrets)
        let rewardHome = try await loadRewardHome(secrets: secrets)
        let info = try await loadInfo(role: role, secrets: secrets)
        return SignInSummary(
            uid: role.uid,
            month: rewardHome.month,
            totalSignDay: info.totalSignDay,
            isTodaySigned: info.isSign,
            rewards: rewardHome.rewards(totalSignDay: info.totalSignDay),
            serverDate: info.today
        )
    }

    func claim(
        role: GenshinRole,
        secrets: AccountSecrets,
        verification: SignInVerificationResult? = nil
    ) async throws -> SignInResultPayload {
        try HoYoLABAPI.validate(role: role, secrets: secrets)
        if secrets.isHoYoLAB {
            let url = Self.hoYoLABRewardURL(endpoint: "sign")
            let body = try JSONEncoder().encode(["act_id": HoYoLABAPI.signInActivityID])
            var request = try HoYoLABAPI.request(url: url, secrets: secrets, method: "POST", body: body)
            request.setValue("hk4e", forHTTPHeaderField: "x-rpc-signgame")
            if let verification {
                request.setValue(verification.challenge, forHTTPHeaderField: "x-rpc-challenge")
                request.setValue(verification.validate, forHTTPHeaderField: "x-rpc-validate")
                request.setValue(verification.seccode, forHTTPHeaderField: "x-rpc-seccode")
            }
            let response: HoYoResponse<HoYoLABSignInPayload> = try await httpClient.send(request)
            if response.retcode == -5003 {
                var payload = response.data?.result ?? SignInResultPayload(success: 1, riskCode: -5003, gt: nil, challenge: nil)
                payload.riskCode = -5003
                return payload
            }
            // HoYoLAB may return an empty data object for a successful claim.
            // The session service independently confirms is_sign after claiming.
            var payload = try response.requireDataPreservingRetcode().result
            if payload.isRisk == true || payload.riskCode.map({ $0 != 0 }) == true || payload.success == 1 {
                payload.isRisk = true
                return payload
            }
            return SignInResultPayload(code: "ok", success: 0, riskCode: nil, gt: nil, challenge: nil)
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/sign")!
        let body = try JSONEncoder().encode(SignInData(uid: role.uid, region: role.region))
        var request = try signedRequest(url: url, method: "POST", body: body, secrets: secrets, verification: verification)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response: HoYoResponse<SignInResultPayload> = try await httpClient.send(request)
        return try Self.signInResult(from: response)
    }

    func loadResignInfo(role: GenshinRole, secrets: AccountSecrets) async throws -> SignInResignInfoPayload {
        guard !secrets.isHoYoLAB else {
            throw AccountSessionError.apiFailure("HoYoLAB 不支持米游社补签")
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/resign_info?lang=zh-cn&act_id=\(HoYoConstants.lunaActivityID)&uid=\(role.uid)&region=\(role.region)")!
        let request = try signedRequest(url: url, method: "GET", body: nil, secrets: secrets)
        let response: HoYoResponse<SignInResignInfoPayload> = try await httpClient.send(request)
        return try response.requireData()
    }

    func resign(
        role: GenshinRole,
        secrets: AccountSecrets,
        verification: SignInVerificationResult? = nil
    ) async throws -> SignInResultPayload {
        guard !secrets.isHoYoLAB else {
            throw AccountSessionError.apiFailure("HoYoLAB 不支持米游社补签")
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/resign?lang=zh-cn")!
        let body = try JSONEncoder().encode(SignInData(uid: role.uid, region: role.region))
        var request = try signedRequest(url: url, method: "POST", body: body, secrets: secrets, verification: verification)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response: HoYoResponse<SignInResultPayload> = try await httpClient.send(request)
        return try Self.signInResult(from: response)
    }

    static func signInResult(from response: HoYoResponse<SignInResultPayload>) throws -> SignInResultPayload {
        if response.retcode == -5003 {
            if var payload = response.data {
                if payload.riskCode == nil {
                    payload.riskCode = response.retcode
                }
                return payload
            }
            return SignInResultPayload(success: 0, riskCode: response.retcode, gt: nil, challenge: nil)
        }
        return try response.requireData()
    }

    private func loadRewardHome(secrets: AccountSecrets) async throws -> SignInRewardHomePayload {
        if secrets.isHoYoLAB {
            let request = try HoYoLABAPI.request(url: Self.hoYoLABRewardURL(endpoint: "home"), secrets: secrets)
            let response: HoYoResponse<SignInRewardHomePayload> = try await httpClient.send(request)
            return try response.requireDataPreservingRetcode()
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/home?lang=zh-cn&act_id=\(HoYoConstants.lunaActivityID)")!
        let request = try signedRequest(url: url, method: "GET", body: nil, secrets: secrets)
        let response: HoYoResponse<SignInRewardHomePayload> = try await httpClient.send(request)
        return try response.requireData()
    }

    private func loadInfo(role: GenshinRole, secrets: AccountSecrets) async throws -> SignInInfoPayload {
        if secrets.isHoYoLAB {
            let request = try HoYoLABAPI.request(url: Self.hoYoLABRewardURL(endpoint: "info"), secrets: secrets)
            let response: HoYoResponse<SignInInfoPayload> = try await httpClient.send(request)
            return try response.requireDataPreservingRetcode()
        }
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/info?lang=zh-cn&act_id=\(HoYoConstants.lunaActivityID)&uid=\(role.uid)&region=\(role.region)")!
        let request = try signedRequest(url: url, method: "GET", body: nil, secrets: secrets)
        let response: HoYoResponse<SignInInfoPayload> = try await httpClient.send(request)
        return try response.requireData()
    }

    private static func hoYoLABRewardURL(endpoint: String) -> URL {
        URL(string: "https://sg-hk4e-api.hoyolab.com/event/sol/\(endpoint)?act_id=\(HoYoLABAPI.signInActivityID)&lang=\(HoYoLABAPI.language)")!
    }

    private func signedRequest(
        url: URL,
        method: String,
        body: Data?,
        secrets: AccountSecrets,
        verification: SignInVerificationResult? = nil
    ) throws -> URLRequest {
        guard let cookieToken = secrets.cookieToken, !cookieToken.isEmpty else {
            throw AccountSessionError.missingAccount
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        request.setValue(HoYoRequestSigner.cookieHeader(for: secrets, kind: .cookieToken), forHTTPHeaderField: "Cookie")
        request.setValue(HoYoRequestSigner.dsHeader(url: url, body: bodyString, version: .gen1, salt: HoYoSalt.cnLK2, includeLetters: true), forHTTPHeaderField: "DS")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HoYoConstants.cnAppVersion, forHTTPHeaderField: "x-rpc-app_version")
        request.setValue("5", forHTTPHeaderField: "x-rpc-client_type")
        request.setValue(HoYoConstants.deviceID, forHTTPHeaderField: "x-rpc-device_id")
        request.setValue("hk4e", forHTTPHeaderField: "x-rpc-signgame")
        if let verification {
            request.setValue(verification.challenge, forHTTPHeaderField: "x-rpc-challenge")
            request.setValue(verification.validate, forHTTPHeaderField: "x-rpc-validate")
            request.setValue(verification.seccode, forHTTPHeaderField: "x-rpc-seccode")
        }
        request.setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}
