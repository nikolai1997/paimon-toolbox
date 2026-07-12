import Foundation

struct LocalAccountStatus: Equatable {
    var isSignedIn: Bool
    var nickname: String?
    var avatarURL: URL? = nil
    var accountID: String?
    var selectedRole: GenshinRole?
    var signInSummary: SignInSummary?
    var sessionMessage: String?
    var lastCheckInDate: Date?

    static let signedOut = LocalAccountStatus(
        isSignedIn: false,
        nickname: nil,
        avatarURL: nil,
        accountID: nil,
        selectedRole: nil,
        signInSummary: nil,
        sessionMessage: nil,
        lastCheckInDate: nil
    )
}

struct MiHoYoAccount: Codable, Equatable, Identifiable {
    var id: String { accountID }
    var accountID: String
    var mid: String
    var nickname: String?
    var avatarURL: URL? = nil
}

struct GenshinRole: Codable, Equatable, Identifiable {
    var id: String { uid }
    var uid: String
    var region: String
    var nickname: String
    var level: Int
    var isSelected: Bool
}

struct AccountSecrets: Codable, Equatable {
    var stuid: String
    var stoken: String
    var mid: String
    var cookieToken: String?
    var ltoken: String?
}

struct AccountVerificationState: Equatable {
    var message: String
    var url: URL
    var payload: SignInResultPayload?
    var webContext: SignInWebVerificationContext?
    var purpose: AccountVerificationPurpose = .dailySignIn
}

enum AccountVerificationPurpose: Equatable {
    case dailySignIn
    case resign
}

struct SignInVerificationResult: Codable, Equatable {
    var challenge: String
    var validate: String
    var seccode: String

    init(challenge: String, validate: String, seccode: String? = nil) {
        self.challenge = challenge
        self.validate = validate
        self.seccode = seccode ?? "\(validate)|jordan"
    }

    enum CodingKeys: String, CodingKey {
        case challenge = "geetest_challenge"
        case validate = "geetest_validate"
        case seccode = "geetest_seccode"
    }
}

struct SignInWebVerificationContext: Equatable {
    var url: URL
    var accountID: String
    var mid: String? = nil
    var nickname: String? = nil
    var avatarURL: URL? = nil
    var cookieToken: String
    var ltoken: String?
    var selectedRole: GenshinRole? = nil

    var cookies: [AccountWebCookie] {
        var result = [
            AccountWebCookie(name: "account_id", value: accountID),
            AccountWebCookie(name: "account_id_v2", value: accountID),
            AccountWebCookie(name: "cookie_token", value: cookieToken),
            AccountWebCookie(name: "cookie_token_v2", value: cookieToken)
        ]
        if let mid, !mid.isEmpty {
            result.append(AccountWebCookie(name: "ltmid", value: mid))
            result.append(AccountWebCookie(name: "ltmid_v2", value: mid))
        }
        if let ltoken, !ltoken.isEmpty {
            result.append(AccountWebCookie(name: "ltuid", value: accountID))
            result.append(AccountWebCookie(name: "ltuid_v2", value: accountID))
            result.append(AccountWebCookie(name: "ltoken", value: ltoken))
            result.append(AccountWebCookie(name: "ltoken_v2", value: ltoken))
        }
        return result
    }

    var cookieHeader: String {
        cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    var userInfo: [String: AnyHashable] {
        [
            "id": accountID,
            "uid": accountID,
            "account_id": accountID,
            "accountId": accountID,
            "mid": mid ?? "",
            "gender": 0,
            "nickname": nickname ?? "",
            "introduce": "",
            "avatar_url": avatarURL?.absoluteString ?? ""
        ]
    }

    var selectedGameRole: [String: AnyHashable]? {
        guard let selectedRole else {
            return nil
        }
        return [
            "game_biz": "hk4e_cn",
            "gameBiz": "hk4e_cn",
            "game_uid": selectedRole.uid,
            "gameUid": selectedRole.uid,
            "region": selectedRole.region,
            "region_name": selectedRole.region,
            "regionName": selectedRole.region,
            "nickname": selectedRole.nickname,
            "level": selectedRole.level,
            "is_chosen": selectedRole.isSelected,
            "isChosen": selectedRole.isSelected,
            "is_official": true,
            "isOfficial": true
        ]
    }
}

struct AccountWebCookie: Equatable {
    var name: String
    var value: String
}

struct QrLoginSession: Codable, Equatable {
    var qrURL: URL
    var ticket: String

    enum CodingKeys: String, CodingKey {
        case qrURL = "url"
        case ticket
    }
}

enum QrLoginPollingState: Equatable {
    case idle
    case waiting
    case scanned
    case confirmed
    case expired
    case canceled
    case failed(String)
}

struct HoYoResponse<T: Decodable>: Decodable {
    var retcode: Int
    var message: String
    var data: T?
}

struct SignInInfoPayload: Codable, Equatable {
    var totalSignDay: Int
    var today: String?
    var isSign: Bool

    enum CodingKeys: String, CodingKey {
        case totalSignDay = "total_sign_day"
        case today
        case isSign = "is_sign"
    }
}

struct SignInReward: Codable, Equatable, Identifiable {
    var id: Int { day }
    var day: Int
    var name: String
    var count: Int
    var iconURL: URL?
    var isClaimed: Bool

    enum CodingKeys: String, CodingKey {
        case day
        case name
        case count = "cnt"
        case iconURL = "icon"
        case isClaimed
    }
}

struct SignInSummary: Codable, Equatable {
    var uid: String
    var month: Int
    var totalSignDay: Int
    var isTodaySigned: Bool
    var rewards: [SignInReward]
    var serverDate: String? = nil
}

struct SignInResignInfoPayload: Codable, Equatable {
    var resignCountDaily: Int
    var resignCountMonthly: Int
    var resignLimitDaily: Int
    var resignLimitMonthly: Int
    var signCountMissed: Int
    var coinCount: Int
    var coinCost: Int
    var rule: String?
    var signed: Bool
    var signDays: Int
    var cost: Int
    var monthQualityCount: Int
    var qualityCount: Int

    var canResign: Bool {
        signCountMissed > 0
            && resignCountDaily < resignLimitDaily
            && resignCountMonthly < resignLimitMonthly
            && coinCount >= coinCost
    }

    enum CodingKeys: String, CodingKey {
        case resignCountDaily = "resign_cnt_daily"
        case resignCountMonthly = "resign_cnt_monthly"
        case resignLimitDaily = "resign_limit_daily"
        case resignLimitMonthly = "resign_limit_monthly"
        case signCountMissed = "sign_cnt_missed"
        case coinCount = "coin_cnt"
        case coinCost = "coin_cost"
        case rule
        case signed
        case signDays = "sign_days"
        case cost
        case monthQualityCount = "month_quality_cnt"
        case qualityCount = "quality_cnt"
    }
}

struct SignInResultPayload: Codable, Equatable {
    var code: String?
    var success: Int?
    var riskCode: Int?
    var isRisk: Bool?
    var gt: String?
    var challenge: String?

    init(
        code: String? = nil,
        success: Int?,
        riskCode: Int?,
        isRisk: Bool? = nil,
        gt: String?,
        challenge: String?
    ) {
        self.code = code
        self.success = success
        self.riskCode = riskCode
        self.isRisk = isRisk
        self.gt = gt
        self.challenge = challenge
    }

    enum CodingKeys: String, CodingKey {
        case code
        case success
        case riskCode = "risk_code"
        case isRisk = "is_risk"
        case gt
        case challenge
    }
}
