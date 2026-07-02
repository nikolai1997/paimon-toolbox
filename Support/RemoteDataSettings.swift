import Foundation

enum RemoteDataSettings {
    static let githubMetadataURLKey = "remoteData.githubMetadataURL"
    static let offlinePackageURLKey = "remoteData.offlinePackageURL"
    static let autoRefreshEnabledKey = "remoteData.autoRefreshEnabled"
    static let lastAutoRefreshAttemptKey = "remoteData.lastAutoRefreshAttemptAt"
    static let minimumAutoRefreshInterval: TimeInterval = 24 * 60 * 60

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
        guard let lastAttempt = userDefaults.object(forKey: lastAutoRefreshAttemptKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastAttempt) >= minimumAutoRefreshInterval
    }

    static func markAutoRefreshAttempt(at date: Date, userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: lastAutoRefreshAttemptKey)
    }
}
