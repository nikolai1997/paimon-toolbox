import Foundation

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
    static let completedDayPrefix = "account.autoSignIn.completedDay"
    static let lastFailurePrefix = "account.autoSignIn.lastFailure"
    static let scheduledAttemptPrefix = "account.autoSignIn.scheduledAttempt"
    static let idleWakeInterval: TimeInterval = 6 * 60 * 60
    static let deferredWakeInterval: TimeInterval = 30 * 60
    static let minimumWakeInterval: TimeInterval = 60
    static let failureCooldown: TimeInterval = 10 * 60
    static let morningWindowStartHour = 8
    static let morningWindowEndHour = 12

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
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
