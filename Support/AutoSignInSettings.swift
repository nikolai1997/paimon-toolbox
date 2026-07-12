import Foundation

enum AutoSignInWindow: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:
            return "上午"
        case .afternoon:
            return "中午"
        case .evening:
            return "晚上"
        }
    }

    var timeRangeText: String {
        switch self {
        case .morning:
            return "08:00-12:00"
        case .afternoon:
            return "12:00-16:00"
        case .evening:
            return "18:00-22:00"
        }
    }

    var startHour: Int {
        switch self {
        case .morning:
            return 8
        case .afternoon:
            return 12
        case .evening:
            return 18
        }
    }

    var endHour: Int {
        switch self {
        case .morning:
            return 12
        case .afternoon:
            return 16
        case .evening:
            return 22
        }
    }
}

protocol AutoSignInStoring: AnyObject {
    var isEnabled: Bool { get }
    func completedDay(accountID: String, uid: String) -> String?
    func setCompletedDay(_ day: String, accountID: String, uid: String)
    func lastFailureDate(accountID: String, uid: String) -> Date?
    func setLastFailureDate(_ date: Date?, accountID: String, uid: String)
    func scheduledAttemptDate(accountID: String, uid: String, serverDay: String) -> Date?
    func setScheduledAttemptDate(_ date: Date, accountID: String, uid: String, serverDay: String)
}

enum AutoSignInSettings {
    static let enabledKey = "account.autoSignIn.enabled"
    static let windowKey = "account.autoSignIn.window"
    static let completedDayPrefix = "account.autoSignIn.completedDay"
    static let lastFailurePrefix = "account.autoSignIn.lastFailure"
    static let scheduledAttemptPrefix = "account.autoSignIn.scheduledAttempt"
    static let idleWakeInterval: TimeInterval = 6 * 60 * 60
    static let deferredWakeInterval: TimeInterval = 30 * 60
    static let minimumWakeInterval: TimeInterval = 60
    static let failureCooldown: TimeInterval = 10 * 60
    static let riskStatusConfirmationAttempts = 2
    static let riskStatusConfirmationDelayNanoseconds: UInt64 = 1_500_000_000
    static let defaultWindow = AutoSignInWindow.morning
    static let morningWindowStartHour = AutoSignInWindow.morning.startHour
    static let morningWindowEndHour = AutoSignInWindow.morning.endHour

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var selectedWindow: AutoSignInWindow {
        AutoSignInWindow(rawValue: UserDefaults.standard.string(forKey: windowKey) ?? "") ?? defaultWindow
    }

    static func scheduledAttemptIdentifier(
        serverDay: String,
        window: AutoSignInWindow = selectedWindow
    ) -> String {
        "\(serverDay).\(window.rawValue)"
    }
}

final class UserDefaultsAutoSignInStore: AutoSignInStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: AutoSignInSettings.enabledKey)
    }

    func completedDay(accountID: String, uid: String) -> String? {
        defaults.string(forKey: completedDayKey(accountID: accountID, uid: uid))
    }

    func setCompletedDay(_ day: String, accountID: String, uid: String) {
        defaults.set(day, forKey: completedDayKey(accountID: accountID, uid: uid))
    }

    func lastFailureDate(accountID: String, uid: String) -> Date? {
        let value = defaults.double(forKey: lastFailureKey(accountID: accountID, uid: uid))
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    func setLastFailureDate(_ date: Date?, accountID: String, uid: String) {
        let key = lastFailureKey(accountID: accountID, uid: uid)
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func scheduledAttemptDate(accountID: String, uid: String, serverDay: String) -> Date? {
        let value = defaults.double(forKey: scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay))
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    func setScheduledAttemptDate(_ date: Date, accountID: String, uid: String, serverDay: String) {
        defaults.set(
            date.timeIntervalSince1970,
            forKey: scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay)
        )
    }

    private func completedDayKey(accountID: String, uid: String) -> String {
        "\(AutoSignInSettings.completedDayPrefix).\(accountID).\(uid)"
    }

    private func lastFailureKey(accountID: String, uid: String) -> String {
        "\(AutoSignInSettings.lastFailurePrefix).\(accountID).\(uid)"
    }

    private func scheduledAttemptKey(accountID: String, uid: String, serverDay: String) -> String {
        "\(AutoSignInSettings.scheduledAttemptPrefix).\(accountID).\(uid).\(serverDay)"
    }
}
