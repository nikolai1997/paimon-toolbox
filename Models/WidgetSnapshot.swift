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

    init(
        isSignedIn: Bool,
        nickname: String?,
        uid: String?,
        isTodaySigned: Bool,
        totalSignDay: Int,
        statusText: String,
        actionTitle: String,
        message: String?
    ) {
        self.isSignedIn = isSignedIn
        self.nickname = nickname
        self.uid = uid
        self.isTodaySigned = isTodaySigned
        self.totalSignDay = totalSignDay
        self.statusText = statusText
        self.actionTitle = actionTitle
        self.message = message
    }

    static let signedOut = WidgetSignInSnapshot(
        isSignedIn: false,
        nickname: nil,
        uid: nil,
        isTodaySigned: false,
        totalSignDay: 0,
        statusText: "未登录",
        actionTitle: "去登录",
        message: "登录后显示签到状态"
    )
}

struct WidgetGachaSnapshot: Codable, Equatable {
    var totalPulls: Int
    var fiveStarCount: Int
    var fourStarCount: Int
    var pitySinceLastFiveStar: Int
    var lastFiveStarName: String
    var lastFiveStarDate: Date?
    var characterPulls: Int
    var weaponPulls: Int
    var standardPulls: Int

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
        self.totalPulls = totalPulls
        self.fiveStarCount = fiveStarCount
        self.fourStarCount = fourStarCount
        self.pitySinceLastFiveStar = pitySinceLastFiveStar
        self.lastFiveStarName = lastFiveStarName
        self.lastFiveStarDate = lastFiveStarDate
        self.characterPulls = characterPulls
        self.weaponPulls = weaponPulls
        self.standardPulls = standardPulls
    }

    static let empty = WidgetGachaSnapshot(
        totalPulls: 0,
        fiveStarCount: 0,
        fourStarCount: 0,
        pitySinceLastFiveStar: 0,
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
