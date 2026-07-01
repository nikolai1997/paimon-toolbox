import Foundation

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
        let rewardHome = try await loadRewardHome(secrets: secrets)
        let info = try await loadInfo(role: role, secrets: secrets)
        return SignInSummary(
            uid: role.uid,
            month: rewardHome.month,
            totalSignDay: info.totalSignDay,
            isTodaySigned: info.isSign,
            rewards: rewardHome.rewards(totalSignDay: info.totalSignDay)
        )
    }

    func claim(
        role: GenshinRole,
        secrets: AccountSecrets,
        verification: SignInVerificationResult? = nil
    ) async throws -> SignInResultPayload {
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/sign")!
        let body = try JSONEncoder().encode(SignInData(uid: role.uid, region: role.region))
        var request = try signedRequest(url: url, method: "POST", body: body, secrets: secrets, verification: verification)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response: HoYoResponse<SignInResultPayload> = try await httpClient.send(request)
        return try Self.signInResult(from: response)
    }

    func loadResignInfo(role: GenshinRole, secrets: AccountSecrets) async throws -> SignInResignInfoPayload {
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
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/home?lang=zh-cn&act_id=\(HoYoConstants.lunaActivityID)")!
        let request = try signedRequest(url: url, method: "GET", body: nil, secrets: secrets)
        let response: HoYoResponse<SignInRewardHomePayload> = try await httpClient.send(request)
        return try response.requireData()
    }

    private func loadInfo(role: GenshinRole, secrets: AccountSecrets) async throws -> SignInInfoPayload {
        let url = URL(string: "https://api-takumi.mihoyo.com/event/luna/info?lang=zh-cn&act_id=\(HoYoConstants.lunaActivityID)&uid=\(role.uid)&region=\(role.region)")!
        let request = try signedRequest(url: url, method: "GET", body: nil, secrets: secrets)
        let response: HoYoResponse<SignInInfoPayload> = try await httpClient.send(request)
        return try response.requireData()
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
