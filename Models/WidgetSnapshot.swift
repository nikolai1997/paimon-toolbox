import Foundation

struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var signIn: WidgetSignInSnapshot
    var gacha: WidgetGachaSnapshot
    var planner: WidgetPlannerSnapshot

    static let empty = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        signIn: .signedOut,
        gacha: .empty,
        planner: .empty
    )

    var hasDisplayableContent: Bool {
        signIn.isSignedIn || gacha.totalPulls > 0 || !planner.rows.isEmpty
    }
}

struct WidgetSignInSnapshot: Codable, Equatable {
    var isSignedIn: Bool
    var nickname: String?
    var uid: String?
    var isTodaySigned: Bool
    var totalSignDay: Int
    var statusText: String
    var actionTitle: String
    var message: String?
    var serverDate: String?
    var serverTimeZoneSecondsFromGMT: Int?

    init(
        isSignedIn: Bool,
        nickname: String?,
        uid: String?,
        isTodaySigned: Bool,
        totalSignDay: Int,
        statusText: String,
        actionTitle: String,
        message: String?,
        serverDate: String? = nil,
        serverTimeZoneSecondsFromGMT: Int? = nil
    ) {
        self.isSignedIn = isSignedIn
        self.nickname = nickname
        self.uid = uid
        self.isTodaySigned = isTodaySigned
        self.totalSignDay = totalSignDay
        self.statusText = statusText
        self.actionTitle = actionTitle
        self.message = message
        self.serverDate = serverDate
        self.serverTimeZoneSecondsFromGMT = serverTimeZoneSecondsFromGMT
    }

    func isSignedToday(at date: Date) -> Bool {
        guard isSignedIn,
              isTodaySigned,
              let serverDate,
              let offset = serverTimeZoneSecondsFromGMT,
              let timeZone = TimeZone(secondsFromGMT: offset) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return dateKey == serverDate
    }

    func normalized(at date: Date) -> WidgetSignInSnapshot {
        guard isTodaySigned, !isSignedToday(at: date) else { return self }
        var copy = self
        copy.isTodaySigned = false
        copy.statusText = isSignedIn ? "待签到" : statusText
        copy.actionTitle = isSignedIn ? "去签到" : actionTitle
        return copy
    }

    static let signedOut = WidgetSignInSnapshot(
        isSignedIn: false,
        nickname: nil,
        uid: nil,
        isTodaySigned: false,
        totalSignDay: 0,
        statusText: "未登录",
        actionTitle: "去登录",
        message: "登录后显示签到状态",
        serverDate: nil,
        serverTimeZoneSecondsFromGMT: nil
    )
}

extension WidgetSnapshot {
    func normalized(at date: Date) -> WidgetSnapshot {
        var copy = self
        copy.signIn = signIn.normalized(at: date)
        return copy
    }
}

struct WidgetGachaSnapshot: Codable, Equatable {
    var totalPulls: Int
    var fiveStarCount: Int
    var fourStarCount: Int
    var activityPity: Int
    var standardPity: Int
    var lastFiveStarName: String
    var lastFiveStarDate: Date?
    var characterPulls: Int
    var weaponPulls: Int
    var standardPulls: Int

    var pitySinceLastFiveStar: Int { activityPity }

    init(
        totalPulls: Int,
        fiveStarCount: Int,
        fourStarCount: Int,
        activityPity: Int,
        standardPity: Int,
        lastFiveStarName: String,
        lastFiveStarDate: Date?,
        characterPulls: Int,
        weaponPulls: Int,
        standardPulls: Int
    ) {
        self.totalPulls = totalPulls
        self.fiveStarCount = fiveStarCount
        self.fourStarCount = fourStarCount
        self.activityPity = activityPity
        self.standardPity = standardPity
        self.lastFiveStarName = lastFiveStarName
        self.lastFiveStarDate = lastFiveStarDate
        self.characterPulls = characterPulls
        self.weaponPulls = weaponPulls
        self.standardPulls = standardPulls
    }

    init(
        totalPulls: Int,
        fiveStarCount: Int,
        fourStarCount: Int,
        pitySinceLastFiveStar: Int,
        lastFiveStarName: String,
        lastFiveStarDate: Date?,
        characterPulls: Int,
        weaponPulls: Int,
        standardPulls: Int
    ) {
        self.init(
            totalPulls: totalPulls,
            fiveStarCount: fiveStarCount,
            fourStarCount: fourStarCount,
            activityPity: pitySinceLastFiveStar,
            standardPity: 0,
            lastFiveStarName: lastFiveStarName,
            lastFiveStarDate: lastFiveStarDate,
            characterPulls: characterPulls,
            weaponPulls: weaponPulls,
            standardPulls: standardPulls
        )
    }

    private enum CodingKeys: String, CodingKey {
        case totalPulls
        case fiveStarCount
        case fourStarCount
        case activityPity
        case standardPity
        case pitySinceLastFiveStar
        case lastFiveStarName
        case lastFiveStarDate
        case characterPulls
        case weaponPulls
        case standardPulls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPity = try container.decodeIfPresent(Int.self, forKey: .pitySinceLastFiveStar) ?? 0
        self.init(
            totalPulls: try container.decode(Int.self, forKey: .totalPulls),
            fiveStarCount: try container.decode(Int.self, forKey: .fiveStarCount),
            fourStarCount: try container.decode(Int.self, forKey: .fourStarCount),
            activityPity: try container.decodeIfPresent(Int.self, forKey: .activityPity) ?? legacyPity,
            standardPity: try container.decodeIfPresent(Int.self, forKey: .standardPity) ?? 0,
            lastFiveStarName: try container.decode(String.self, forKey: .lastFiveStarName),
            lastFiveStarDate: try container.decodeIfPresent(Date.self, forKey: .lastFiveStarDate),
            characterPulls: try container.decode(Int.self, forKey: .characterPulls),
            weaponPulls: try container.decode(Int.self, forKey: .weaponPulls),
            standardPulls: try container.decode(Int.self, forKey: .standardPulls)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalPulls, forKey: .totalPulls)
        try container.encode(fiveStarCount, forKey: .fiveStarCount)
        try container.encode(fourStarCount, forKey: .fourStarCount)
        try container.encode(activityPity, forKey: .activityPity)
        try container.encode(standardPity, forKey: .standardPity)
        try container.encode(activityPity, forKey: .pitySinceLastFiveStar)
        try container.encode(lastFiveStarName, forKey: .lastFiveStarName)
        try container.encodeIfPresent(lastFiveStarDate, forKey: .lastFiveStarDate)
        try container.encode(characterPulls, forKey: .characterPulls)
        try container.encode(weaponPulls, forKey: .weaponPulls)
        try container.encode(standardPulls, forKey: .standardPulls)
    }

    static let empty = WidgetGachaSnapshot(
        totalPulls: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        activityPity: 0,
        standardPity: 0,
        lastFiveStarName: "暂无五星记录",
        lastFiveStarDate: nil,
        characterPulls: 0,
        weaponPulls: 0,
        standardPulls: 0
    )
}

struct WidgetPlannerSnapshot: Codable, Equatable {
    var rows: [WidgetPlannerRow]

    static let empty = WidgetPlannerSnapshot(rows: [])

    init(rows: [WidgetPlannerRow]) {
        self.rows = rows
    }
}

struct WidgetPlannerRow: Codable, Equatable, Identifiable {
    var id: UUID
    var targetName: String
    var materialName: String
    var owned: Int
    var required: Int
    var completion: Double

    init(
        id: UUID,
        targetName: String,
        materialName: String,
        owned: Int,
        required: Int,
        completion: Double
    ) {
        self.id = id
        self.targetName = targetName
        self.materialName = materialName
        self.owned = owned
        self.required = required
        self.completion = completion
    }
}
