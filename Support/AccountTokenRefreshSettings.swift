import Foundation

protocol AccountTokenRefreshStoring: AnyObject {
    func lastRefreshDate(accountID: String) -> Date?
    func setLastRefreshDate(_ date: Date, accountID: String)
}

enum AccountTokenRefreshSettings {
    static let lastRefreshPrefix = "account.tokenRefresh.lastRefresh"
    static let minimumRefreshInterval: TimeInterval = 60 * 60 * 24
}

final class UserDefaultsAccountTokenRefreshStore: AccountTokenRefreshStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastRefreshDate(accountID: String) -> Date? {
        let value = defaults.double(forKey: key(for: accountID))
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    func setLastRefreshDate(_ date: Date, accountID: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key(for: accountID))
    }

    private func key(for accountID: String) -> String {
        "\(AccountTokenRefreshSettings.lastRefreshPrefix).\(accountID)"
    }
}
