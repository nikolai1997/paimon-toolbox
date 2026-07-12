import Foundation

enum RemoteDataSettings {
    static let githubMetadataURLKey = "remoteData.githubMetadataURL"
    static let offlinePackageURLKey = "remoteData.offlinePackageURL"
    static let autoRefreshEnabledKey = "remoteData.autoRefreshEnabled"
    static let lastAutoRefreshAttemptKey = "remoteData.lastAutoRefreshAttemptAt"
    static let lastAutoRefreshSuccessKey = "remoteData.lastAutoRefreshSuccessAt"
    static let lastAutoRefreshFailureKey = "remoteData.lastAutoRefreshFailureAt"
    static let minimumAutoRefreshInterval: TimeInterval = 24 * 60 * 60
    static let minimumFailedAutoRefreshRetryInterval: TimeInterval = 15 * 60
    static let maximumClockSkew: TimeInterval = 5 * 60

    static let defaultGitHubMetadataURLString = "https://nikolai1997.github.io/paimon-toolbox-data/metadata.json"
    static let defaultOfflinePackageURLString = "https://www.jianguoyun.com/p/DcsA6I0Qg4qtDhi61acGIAA"

    static var githubMetadataURLString: String {
        defaultGitHubMetadataURLString
    }

    static var offlinePackageURLString: String {
        UserDefaults.standard.string(forKey: offlinePackageURLKey) ?? defaultOfflinePackageURLString
    }

    static var isAutoRefreshEnabled: Bool {
        if UserDefaults.standard.object(forKey: autoRefreshEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: autoRefreshEnabledKey)
    }

    static func shouldAttemptAutoRefresh(now: Date, userDefaults: UserDefaults = .standard) -> Bool {
        if let lastSuccess = userDefaults.object(forKey: lastAutoRefreshSuccessKey) as? Date {
            if lastSuccess.timeIntervalSince(now) > maximumClockSkew {
                userDefaults.removeObject(forKey: lastAutoRefreshSuccessKey)
            } else if now.timeIntervalSince(lastSuccess) < minimumAutoRefreshInterval {
                return false
            }
        }
        if let lastFailure = userDefaults.object(forKey: lastAutoRefreshFailureKey) as? Date {
            if lastFailure.timeIntervalSince(now) > maximumClockSkew {
                userDefaults.removeObject(forKey: lastAutoRefreshFailureKey)
            } else if now.timeIntervalSince(lastFailure) < minimumFailedAutoRefreshRetryInterval {
                return false
            }
        }
        return true
    }

    static func markAutoRefreshAttempt(at date: Date, userDefaults: UserDefaults = .standard) {
        markAutoRefreshSucceeded(at: date, userDefaults: userDefaults)
    }

    static func markAutoRefreshSucceeded(at date: Date, userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: lastAutoRefreshSuccessKey)
        userDefaults.removeObject(forKey: lastAutoRefreshFailureKey)
        userDefaults.removeObject(forKey: lastAutoRefreshAttemptKey)
    }

    static func markAutoRefreshFailed(at date: Date, userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: lastAutoRefreshFailureKey)
        userDefaults.removeObject(forKey: lastAutoRefreshAttemptKey)
    }
}
