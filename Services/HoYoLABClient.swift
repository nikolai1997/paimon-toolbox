import Foundation

enum HoYoLABServer: String, CaseIterable, Identifiable {
    case asia = "os_asia"
    case america = "os_usa"
    case europe = "os_euro"
    case twHkMo = "os_cht"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .asia: "Asia / 亚洲"
        case .america: "America / 美洲"
        case .europe: "Europe / 欧洲"
        case .twHkMo: "TW, HK, MO / 港澳台"
        }
    }
    var timeZoneHours: Int {
        switch self {
        case .america: -5
        case .europe: 1
        case .asia, .twHkMo: 8
        }
    }
}

struct HoYoLABCredentials {
    static let cookieNames: Set<String> = [
        "ltuid", "ltoken", "ltmid", "ltuid_v2", "ltoken_v2", "ltmid_v2",
        "account_id", "cookie_token", "account_mid",
        "account_id_v2", "cookie_token_v2", "account_mid_v2"
    ]
    let cookies: [String: String]
    let accountID: String

    init(cookieHeader: String) throws {
        var header = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.lowercased().hasPrefix("cookie:") { header = String(header.dropFirst(7)) }
        var values: [String: String] = [:]
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.cookieNames.contains(name) else { continue }
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }) else {
                throw AccountSessionError.invalidResponse("HoYoLAB Cookie 格式无效")
            }
            if let previous = values[name], previous != value {
                throw AccountSessionError.invalidResponse("HoYoLAB Cookie 包含不同的登录态，请重新登录后再试")
            }
            values[name] = value
        }
        let pairs = [("ltuid_v2", "ltoken_v2"), ("ltuid", "ltoken"),
                     ("account_id_v2", "cookie_token_v2"), ("account_id", "cookie_token")]
        guard let pair = pairs.first(where: { values[$0.0] != nil && values[$0.1] != nil }),
              let accountID = values[pair.0], accountID.allSatisfy(\.isNumber) else {
            throw AccountSessionError.invalidResponse("请先登录 HoYoLAB，或导入包含 ltuid_v2 和 ltoken_v2 的 Cookie")
        }
        let ids = ["ltuid", "ltuid_v2", "account_id", "account_id_v2"].compactMap { values[$0] }
        guard ids.allSatisfy({ $0 == accountID }) else {
            throw AccountSessionError.invalidResponse("HoYoLAB Cookie 的账号不一致，请重新登录后再试")
        }
        self.cookies = values
        self.accountID = accountID
    }

    var secrets: AccountSecrets {
        AccountSecrets(
            stuid: accountID, stoken: "", mid: cookies["ltmid_v2"] ?? cookies["account_mid_v2"] ?? "",
            cookieToken: nil, ltoken: nil, hoyolabCookies: cookies
        )
    }

    static func header(for cookies: [String: String]) -> String {
        cookies.keys.filter { cookieNames.contains($0) }.sorted()
            .map { "\($0)=\(cookies[$0]!)" }.joined(separator: "; ")
    }
}

/// The overseas contracts follow genshin.py's routes and DS implementation.
/// https://github.com/seriaati/genshin.py/blob/master/genshin/client/routes.py
enum HoYoLABAPI {
    static let signInActivityID = "e202102251931481"
    static let signInURL = URL(string: "https://act.hoyolab.com/ys/event/signin-sea-v3/index.html?act_id=e202102251931481&lang=en-us")!
    static let notesURL = URL(string: "https://act.hoyolab.com/app/community-game-records-sea/index.html")!
    static let loginURL = URL(string: "https://www.hoyolab.com/home")!
    static let language = "en-us"
    static let allowedAPIHosts: Set<String> = [
        "api-os-takumi.mihoyo.com", "sg-public-api.hoyolab.com",
        "sg-hk4e-api.hoyolab.com", "api-account-os.hoyoverse.com"
    ]

    static func request(
        url: URL, secrets: AccountSecrets, method: String = "GET", body: Data? = nil, signed: Bool = false
    ) throws -> URLRequest {
        guard url.scheme == "https", let host = url.host, allowedAPIHosts.contains(host),
              let cookies = secrets.hoyolabCookies else {
            throw AccountSessionError.invalidResponse("HoYoLAB 请求地址或登录态无效")
        }
        // Validate persisted credentials as well as newly imported ones.
        _ = try HoYoLABCredentials(cookieHeader: HoYoLABCredentials.header(for: cookies))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue(HoYoLABCredentials.header(for: cookies), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://act.hoyolab.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://act.hoyolab.com", forHTTPHeaderField: "Origin")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if signed {
            request.setValue("1.5.0", forHTTPHeaderField: "x-rpc-app_version")
            request.setValue("5", forHTTPHeaderField: "x-rpc-client_type")
            request.setValue(language, forHTTPHeaderField: "x-rpc-language")
            request.setValue(language, forHTTPHeaderField: "x-rpc-lang")
            request.setValue(HoYoRequestSigner.dsHeader(url: url, body: nil, version: .gen1,
                salt: "6s25p5ox5y14umn1p61aqyyvbvvl3lrt", includeLetters: true), forHTTPHeaderField: "DS")
        }
        return request
    }

    static func validate(role: GenshinRole, secrets: AccountSecrets) throws {
        guard role.isHoYoLAB == secrets.isHoYoLAB else {
            throw AccountSessionError.invalidResponse("角色服务器与账号平台不一致，请重新登录")
        }
    }
}
