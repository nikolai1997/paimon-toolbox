import Foundation
import OSLog

/// The only display-data request made by the Mac for the desk. The ornament
/// never calls this endpoint, so a board refresh cannot create a
/// second MiHoYo client fingerprint or retry loop.
struct GenshinDailyNoteClient: Sendable {
    private let httpClient: HoYoHTTPClient
    private let now: @Sendable () -> Date
    private static let logger = Logger(subsystem: "com.nikolai.paimon-toolbox", category: "DailyNoteClient")
    private static let indexPath = "/game_record/app/genshin/api/index"
    private static let dailyNotePath = "/game_record/app/genshin/api/dailyNote"
    private static let webStaticReferer = "https://webstatic.mihoyo.com"
    // Live-verified game-record contract. Keep changes to these values behind
    // an endpoint regression test and a real-account verification pass.
    private static let clientType = "5"
    private static let challengeGame = "2"
    private static let toolVersion = "v5.0.1-ys"

    init(
        httpClient: HoYoHTTPClient = HoYoHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.now = now
    }

    func load(
        role: GenshinRole,
        secrets: AccountSecrets,
        verificationChallenge: String? = nil
    ) async throws -> DeskBridgeDailyNote {
        // Snap Hutao warms the same game-record session with the player index
        // before reading dailyNote. This reduces false 1034 responses and
        // keeps both requests on one client identity.
        try await loadPlayerInfo(
            role: role,
            secrets: secrets,
            verificationChallenge: verificationChallenge
        )

        var components = URLComponents(string: "https://api-takumi-record.mihoyo.com\(Self.dailyNotePath)")!
        components.queryItems = [
            URLQueryItem(name: "role_id", value: role.uid),
            URLQueryItem(name: "server", value: role.region),
        ]
        guard let url = components.url else { throw AccountSessionError.invalidResponse("便签地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyDailyHeaders(to: &request, url: url, body: nil, secrets: secrets, includeWebStaticReferer: true)
        request.setValue(Self.toolVersion, forHTTPHeaderField: "x-rpc-tool_verison")
        if let verificationChallenge, !verificationChallenge.isEmpty {
            request.setValue(verificationChallenge, forHTTPHeaderField: "x-rpc-challenge")
        }

        let response: HoYoResponse<Payload> = try await httpClient.send(request)
        Self.logResponse(response, endpoint: "dailyNote")
        if Self.isVerificationRetcode(response.retcode) {
            throw await verificationError(retcode: response.retcode, secrets: secrets, challengePath: Self.dailyNotePath)
        }
        let payload = try Self.requireData(response)
        let observedAt = now()
        return DeskBridgeDailyNote(
            resin: max(0, payload.currentResin),
            resinMax: max(1, payload.maxResin),
            resinRecoveryAt: Self.recoveryDate(payload.resinRecoveryTime, observedAt: observedAt),
            commissionDone: max(0, payload.finishedTaskNum),
            commissionTotal: max(1, payload.totalTaskNum),
            expeditionFinished: payload.expeditions.filter { $0.status == "Finished" }.count,
            expeditionTotal: max(1, payload.maxExpeditionNum),
            observedAt: observedAt
        )
    }

    /// Completes only the Mac-issued daily-note challenge. The proof is never
    /// sent to the device, and the subsequent read keeps the same challenge
    /// identifier in its request header.
    func verify(
        _ verification: SignInVerificationResult,
        secrets: AccountSecrets,
        challengePath: String?
    ) async throws -> String {
        let url = URL(string: "https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/verifyVerification")!
        let body = try JSONEncoder().encode([
            "geetest_challenge": verification.challenge,
            "geetest_validate": verification.validate,
            "geetest_seccode": verification.seccode,
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        applyDailyHeaders(to: &request, url: url, body: String(data: body, encoding: .utf8), secrets: secrets)
        request.setValue(Self.challengeGame, forHTTPHeaderField: "x-rpc-challenge_game")
        request.setValue(challengePath ?? Self.dailyNotePath, forHTTPHeaderField: "x-rpc-challenge_path")
        let response: HoYoResponse<VerificationResponse> = try await httpClient.send(request)
        Self.logResponse(response, endpoint: "verifyVerification")
        if Self.isVerificationRetcode(response.retcode) {
            throw AccountSessionError.requiresVerification(SignInResultPayload(
                success: 1, riskCode: response.retcode, isRisk: true, gt: nil, challenge: nil
            ))
        }
        let payload = try Self.requireData(response)
        guard let challenge = payload.challenge?.trimmingCharacters(in: .whitespacesAndNewlines),
              !challenge.isEmpty else {
            throw AccountSessionError.invalidResponse("便签验证成功但缺少重试 challenge")
        }
        return challenge
    }

    private func createVerification(secrets: AccountSecrets, challengePath: String) async throws -> VerificationChallenge {
        var components = URLComponents(string: "https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/createVerification")!
        components.queryItems = [URLQueryItem(name: "is_high", value: "true")]
        guard let url = components.url else { throw AccountSessionError.invalidResponse("便签验证地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyDailyHeaders(to: &request, url: url, body: nil, secrets: secrets)
        request.setValue(Self.challengeGame, forHTTPHeaderField: "x-rpc-challenge_game")
        request.setValue(challengePath, forHTTPHeaderField: "x-rpc-challenge_path")
        let response: HoYoResponse<VerificationChallenge> = try await httpClient.send(request)
        guard response.retcode == 0, let challenge = response.data,
              !challenge.gt.isEmpty, !challenge.challenge.isEmpty else {
            throw AccountSessionError.requiresVerification(SignInResultPayload(
                success: 1, riskCode: response.retcode, isRisk: true, gt: nil, challenge: nil
            ))
        }
        return challenge
    }

    private func applyDailyHeaders(
        to request: inout URLRequest,
        url: URL,
        body: String?,
        secrets: AccountSecrets,
        includeWebStaticReferer: Bool = false
    ) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.dailyNoteCookieHeader(for: secrets), forHTTPHeaderField: "Cookie")
        request.setValue(HoYoRequestSigner.dsHeader(url: url, body: body, version: .gen2, salt: HoYoSalt.cnX4, includeLetters: false), forHTTPHeaderField: "DS")
        request.setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(HoYoConstants.cnAppVersion, forHTTPHeaderField: "x-rpc-app_version")
        request.setValue(Self.clientType, forHTTPHeaderField: "x-rpc-client_type")
        request.setValue(HoYoConstants.deviceID, forHTTPHeaderField: "x-rpc-device_id")
        if includeWebStaticReferer {
            request.setValue(Self.webStaticReferer, forHTTPHeaderField: "Referer")
        }
        if let deviceFingerprint = secrets.deviceFingerprint, !deviceFingerprint.isEmpty {
            request.setValue(deviceFingerprint, forHTTPHeaderField: "x-rpc-device_fp")
        }
    }

    private func loadPlayerInfo(
        role: GenshinRole,
        secrets: AccountSecrets,
        verificationChallenge: String?
    ) async throws {
        var components = URLComponents(string: "https://api-takumi-record.mihoyo.com\(Self.indexPath)")!
        components.queryItems = [
            URLQueryItem(name: "role_id", value: role.uid),
            URLQueryItem(name: "server", value: role.region),
        ]
        guard let url = components.url else {
            throw AccountSessionError.invalidResponse("角色资料地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyDailyHeaders(to: &request, url: url, body: nil, secrets: secrets, includeWebStaticReferer: true)
        if let verificationChallenge, !verificationChallenge.isEmpty {
            request.setValue(verificationChallenge, forHTTPHeaderField: "x-rpc-challenge")
        }
        let response: HoYoResponse<IgnorePayload> = try await httpClient.send(request)
        Self.logResponse(response, endpoint: "index")
        if Self.isVerificationRetcode(response.retcode) {
            throw await verificationError(retcode: response.retcode, secrets: secrets, challengePath: Self.indexPath)
        }
        _ = try Self.requireData(response)
    }

    private func verificationError(retcode: Int, secrets: AccountSecrets, challengePath: String) async -> AccountSessionError {
        if let challenge = try? await createVerification(secrets: secrets, challengePath: challengePath) {
            return .requiresVerification(SignInResultPayload(
                success: 1,
                riskCode: retcode,
                isRisk: true,
                gt: challenge.gt,
                challenge: challenge.challenge,
                challengePath: challengePath
            ))
        }
        return .requiresVerification(SignInResultPayload(
            success: 1,
            riskCode: retcode,
            isRisk: true,
            gt: nil,
            challenge: nil,
            challengePath: challengePath
        ))
    }

    private static func requireData<T>(_ response: HoYoResponse<T>) throws -> T {
        guard response.retcode == 0 else {
            if response.retcode == 10306 {
                throw AccountSessionError.invalidResponse("安全验证票据无效，请重新打开验证")
            }
            let message = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AccountSessionError.apiFailureResponse(
                retcode: response.retcode,
                message: message.isEmpty ? "未知接口错误" : message
            )
        }
        guard let data = response.data else {
            throw AccountSessionError.invalidResponse("接口成功响应缺少 data")
        }
        return data
    }

    private static func logResponse<T>(_ response: HoYoResponse<T>, endpoint: String) {
        logger.notice("\(endpoint, privacy: .public) retcode=\(response.retcode, privacy: .public) hasData=\(response.data != nil, privacy: .public) messageEmpty=\(response.message.isEmpty, privacy: .public)")
    }

    private static func isVerificationRetcode(_ retcode: Int) -> Bool {
        retcode == 1034 || abs(retcode) == 5003
    }

    private static func recoveryDate(_ raw: FlexibleInt?, observedAt: Date) -> Date? {
        guard let seconds = raw?.value, seconds > 0 else { return nil }
        return observedAt.addingTimeInterval(TimeInterval(seconds))
    }

    /// Snap Hutao sends game-record reads with CookieToken and LToken only.
    /// Its cookie values are deliberately kept to the original four fields;
    /// the v2 and MID variants belong to browser sessions, not this API read.
    private static func dailyNoteCookieHeader(for secrets: AccountSecrets) -> String {
        var values: [String] = []
        if let cookieToken = secrets.cookieToken, !cookieToken.isEmpty {
            values += [
                "account_id=\(secrets.stuid)",
                "cookie_token=\(cookieToken)",
            ]
        }
        if let ltoken = secrets.ltoken, !ltoken.isEmpty {
            values += [
                "ltuid=\(secrets.stuid)",
                "ltoken=\(ltoken)",
            ]
        }
        return values.joined(separator: ";")
    }
}

private struct Payload: Decodable {
    var currentResin: Int
    var maxResin: Int
    var resinRecoveryTime: FlexibleInt?
    var finishedTaskNum: Int
    var totalTaskNum: Int
    var expeditions: [Expedition]
    var maxExpeditionNum: Int

    enum CodingKeys: String, CodingKey {
        case currentResin = "current_resin"
        case maxResin = "max_resin"
        case resinRecoveryTime = "resin_recovery_time"
        case finishedTaskNum = "finished_task_num"
        case totalTaskNum = "total_task_num"
        case expeditions
        case maxExpeditionNum = "max_expedition_num"
    }

    struct Expedition: Decodable { var status: String }
}

private struct FlexibleInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(String.self) {
            self.value = Int(value)
        } else {
            self.value = nil
        }
    }
}

private struct IgnorePayload: Decodable {
    init(from decoder: Decoder) throws {}
}

private struct VerificationChallenge: Decodable {
    var gt: String
    var challenge: String
}

private struct VerificationResponse: Decodable {
    var challenge: String?
}
