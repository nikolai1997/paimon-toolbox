import Foundation

struct GachaAuthKeyRequest: Encodable {
    var authAppID = "webview_gacha"
    var gameBiz = "hk4e_cn"
    var gameUID: String
    var region: String

    enum CodingKeys: String, CodingKey {
        case authAppID = "auth_appid"
        case gameBiz = "game_biz"
        case gameUID = "game_uid"
        case region
    }
}

struct GachaAuthKeyPayload: Decodable, Equatable {
    var authkey: String
}

struct GachaLogPagePayload: Decodable, Equatable {
    var list: [GachaLogRemoteItem]
}

struct GachaLogRemoteItem: Decodable, Equatable {
    var id: String
    var itemID: String?
    var time: String
    var name: String
    var itemType: String
    var rankType: String
    var gachaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case itemID = "item_id"
        case time
        case name
        case itemType = "item_type"
        case rankType = "rank_type"
        case gachaType = "gacha_type"
    }

    var record: GachaRecord? {
        guard let date = DateFormatter.gachaLogRemote.date(from: time) else {
            return nil
        }
        return GachaRecord(
            itemID: itemID,
            id: id,
            time: date,
            banner: BannerKind(gachaLogType: gachaType),
            name: name,
            itemType: itemType,
            rarity: Int(rankType) ?? 3
        )
    }
}

struct GachaLogRemoteClient: @unchecked Sendable {
    var httpClient = HoYoHTTPClient()
    var pageDelayNanoseconds: UInt64 = 1_200_000_000
    var rateLimitRetryDelaysNanoseconds: [UInt64] = [5_000_000_000, 15_000_000_000, 30_000_000_000]
    var sleep: @Sendable (UInt64) async throws -> Void = { nanoseconds in
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    init(
        httpClient: HoYoHTTPClient = HoYoHTTPClient(),
        pageDelayNanoseconds: UInt64 = 1_200_000_000,
        rateLimitRetryDelaysNanoseconds: [UInt64] = [5_000_000_000, 15_000_000_000, 30_000_000_000],
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.httpClient = httpClient
        self.pageDelayNanoseconds = pageDelayNanoseconds
        self.rateLimitRetryDelaysNanoseconds = rateLimitRetryDelaysNanoseconds
        self.sleep = sleep
    }

    func loadRecords(
        role: GenshinRole,
        secrets: AccountSecrets,
        bannerTypes: [String] = ["301", "400", "302", "500", "200"],
        pageSize: Int = 20,
        maxPagesPerBanner: Int = 500
    ) async throws -> [GachaRecord] {
        let authkey = try await generateAuthKey(role: role, secrets: secrets)
        var records: [GachaRecord] = []
        var didRequestPage = false

        for bannerType in bannerTypes {
            var endID = "0"
            for _ in 0..<maxPagesPerBanner {
                if didRequestPage, pageDelayNanoseconds > 0 {
                    try await sleep(pageDelayNanoseconds)
                }
                let page = try await loadPageWithRateLimit(
                    authkey: authkey,
                    role: role,
                    bannerType: bannerType,
                    endID: endID,
                    pageSize: pageSize
                )
                didRequestPage = true
                let pageRecords = page.list.compactMap(\.record)
                guard !pageRecords.isEmpty else {
                    break
                }
                records.append(contentsOf: pageRecords)
                guard let lastID = page.list.last?.id, !lastID.isEmpty, lastID != endID else {
                    break
                }
                endID = lastID
            }
        }

        return GachaLogDocument.mergedRecords(existing: [], imported: records)
    }

    private func loadPageWithRateLimit(
        authkey: String,
        role: GenshinRole,
        bannerType: String,
        endID: String,
        pageSize: Int
    ) async throws -> GachaLogPagePayload {
        for retryIndex in 0...rateLimitRetryDelaysNanoseconds.count {
            do {
                return try await loadPage(
                    authkey: authkey,
                    role: role,
                    bannerType: bannerType,
                    endID: endID,
                    pageSize: pageSize
                )
            } catch AccountSessionError.apiFailure(let message) where message.isGachaRateLimitMessage {
                guard retryIndex < rateLimitRetryDelaysNanoseconds.count else {
                    throw AccountSessionError.apiFailure("访问过于频繁，请稍后再试")
                }
                try await sleep(rateLimitRetryDelaysNanoseconds[retryIndex])
            }
        }
        throw AccountSessionError.apiFailure("访问过于频繁，请稍后再试")
    }

    private func generateAuthKey(role: GenshinRole, secrets: AccountSecrets) async throws -> String {
        guard !secrets.stoken.isEmpty else {
            throw AccountSessionError.missingAccount
        }

        let url = URL(string: "https://api-takumi.mihoyo.com/binding/api/genAuthKey")!
        let body = try JSONEncoder().encode(GachaAuthKeyRequest(gameUID: role.uid, region: role.region))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        let bodyString = String(data: body, encoding: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HoYoConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(HoYoRequestSigner.cookieHeader(for: secrets, kind: .stoken), forHTTPHeaderField: "Cookie")
        request.setValue(
            HoYoRequestSigner.dsHeader(url: url, body: bodyString, version: .gen2, salt: HoYoSalt.cnX4, includeLetters: true),
            forHTTPHeaderField: "DS"
        )
        request.setValue(HoYoConstants.cnAppVersion, forHTTPHeaderField: "x-rpc-app_version")
        request.setValue("5", forHTTPHeaderField: "x-rpc-client_type")
        request.setValue(HoYoConstants.deviceID, forHTTPHeaderField: "x-rpc-device_id")
        request.setValue("hk4e", forHTTPHeaderField: "x-rpc-signgame")

        let response: HoYoResponse<GachaAuthKeyPayload> = try await httpClient.send(request)
        return try response.requireData().authkey
    }

    private func loadPage(
        authkey: String,
        role: GenshinRole,
        bannerType: String,
        endID: String,
        pageSize: Int
    ) async throws -> GachaLogPagePayload {
        var components = URLComponents(string: "https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog")!
        components.queryItems = [
            URLQueryItem(name: "authkey_ver", value: "1"),
            URLQueryItem(name: "sign_type", value: "2"),
            URLQueryItem(name: "auth_appid", value: "webview_gacha"),
            URLQueryItem(name: "authkey", value: authkey),
            URLQueryItem(name: "game_biz", value: "hk4e_cn"),
            URLQueryItem(name: "lang", value: HoYoConstants.languageCode),
            URLQueryItem(name: "region", value: role.region),
            URLQueryItem(name: "gacha_type", value: bannerType),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: "\(pageSize)"),
            URLQueryItem(name: "end_id", value: endID)
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            throw AccountSessionError.invalidResponse("invalid gacha log URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HoYoConstants.mobileUserAgent, forHTTPHeaderField: "User-Agent")
        let response: HoYoResponse<GachaLogPagePayload> = try await httpClient.send(request)
        return try response.requireData()
    }
}

private extension DateFormatter {
    static let gachaLogRemote: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension BannerKind {
    init(gachaLogType: String?) {
        switch gachaLogType {
        case "400":
            self = .characterEvent2
        case "302":
            self = .weapon
        case "500":
            self = .chronicled
        case "200":
            self = .standard
        default:
            self = .character
        }
    }
}

private extension String {
    var isGachaRateLimitMessage: Bool {
        localizedCaseInsensitiveContains("visit too frequently")
            || localizedStandardContains("访问过于频繁")
    }
}
