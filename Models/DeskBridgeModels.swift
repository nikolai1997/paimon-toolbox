import Foundation

struct DeskBridgeRole: Codable, Equatable {
    var uid: String
    var region: String
    var nickname: String
    var level: Int

    init(_ role: GenshinRole) {
        uid = role.uid
        region = role.region
        nickname = role.nickname
        level = role.level
    }
}

struct DeskBridgeSnapshot: Codable, Equatable {
    var accountID: String?
    var nickname: String?
    var role: DeskBridgeRole?
    var signedToday: Bool?
    var signDayCount: Int?
    var resin: Int?
    var resinMax: Int?
    var resinRecoveryAt: Date?
    var commissionDone: Int?
    var commissionTotal: Int?
    var expeditionFinished: Int?
    var expeditionTotal: Int?
    var refreshedAt: Date?
    var status: String
    var message: String?
    var codex: DeskCodexUsage?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case nickname, role
        case signedToday = "signed_today"
        case signDayCount = "sign_day_count"
        case resin
        case resinMax = "resin_max"
        case resinRecoveryAt = "resin_recovery_at"
        case commissionDone = "commission_done"
        case commissionTotal = "commission_total"
        case expeditionFinished = "expedition_finished"
        case expeditionTotal = "expedition_total"
        case refreshedAt = "refreshed_at"
        case status, message, codex
    }
}

/// Display-only data written by the independent Codex Companion.  It contains
/// no Codex credential, prompt, response, or account identity.
struct DeskCodexUsage: Codable, Equatable {
    var remainingPercent: Int?
    var resetDisplay: String?
    var weeklyRemainingPercent: Int?
    var weeklyResetDisplay: String?

    enum CodingKeys: String, CodingKey {
        case remainingPercent = "remaining_percent"
        case resetDisplay = "reset_display"
        case weeklyRemainingPercent = "weekly_remaining_percent"
        case weeklyResetDisplay = "weekly_reset_display"
    }
}

/// A local-Mac observation of the daily note.  It deliberately has no cookie,
/// token, device fingerprint, or verification material.
struct DeskBridgeDailyNote: Codable, Equatable, Sendable {
    var resin: Int
    var resinMax: Int
    var resinRecoveryAt: Date?
    var commissionDone: Int
    var commissionTotal: Int
    var expeditionFinished: Int
    var expeditionTotal: Int
    var observedAt: Date

    enum CodingKeys: String, CodingKey {
        case resin
        case resinMax = "resin_max"
        case resinRecoveryAt = "resin_recovery_at"
        case commissionDone = "commission_done"
        case commissionTotal = "commission_total"
        case expeditionFinished = "expedition_finished"
        case expeditionTotal = "expedition_total"
        case observedAt = "observed_at"
    }
}

/// A short-lived request created by a desk that discovered the Mac toolbox.
/// The display code is intentionally the only value shown to the user; the
/// bearer token is generated only after the user explicitly approves it.
struct DeskDirectPairingRequest: Codable, Equatable, Identifiable {
    var requestID: String
    var deviceID: String
    var displayCode: String
    var createdAt: Date
    var status: String

    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case deviceID = "device_id"
        case displayCode = "display_code"
        case createdAt = "created_at"
        case status
    }
}

struct DeskDirectDeviceRecord: Codable, Equatable {
    var deviceID: String
    var accountID: String
    var accessToken: String
    var pairedAt: Date
    var expiresAt: Date? = nil
    var name: String?
    var host: String?
    var lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case accountID = "account_id"
        case accessToken = "access_token"
        case pairedAt = "paired_at"
        case expiresAt = "expires_at"
        case name, host
        case lastSeenAt = "last_seen_at"
    }
}
