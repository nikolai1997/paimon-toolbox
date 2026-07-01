import Foundation

protocol AccountSecretStoring {
    func load(accountID: String) throws -> AccountSecrets?
    func save(_ secrets: AccountSecrets, accountID: String) throws
    func delete(accountID: String) throws
}

struct LocalAccountSecretStore: AccountSecretStoring {
    private var url: URL
    private var fallbackURLs: [URL]

    init(url: URL? = nil) throws {
        let resolvedURL = try url ?? AppPaths.accountSecretsURL
        self.url = resolvedURL
        self.fallbackURLs = try [Self.legacyAccountSecretsURL()]
            .filter { $0 != resolvedURL }
    }

    init(url: URL, fallbackURLs: [URL] = []) {
        self.url = url
        self.fallbackURLs = fallbackURLs.filter { $0 != url }
    }

    static func legacyAccountSecretsURL() throws -> URL {
        try AppPaths.legacyAppSupportDirectoryURL().appending(path: "account-secrets.json")
    }

    func load(accountID: String) throws -> AccountSecrets? {
        var secrets = try loadAllSecrets()
        if let accountSecrets = secrets[accountID] {
            return accountSecrets
        }

        for fallbackURL in fallbackURLs where FileManager.default.fileExists(atPath: fallbackURL.path) {
            guard let fallbackSecrets = try? LocalEncryptedJSONFile(fileURL: fallbackURL).load([String: AccountSecrets].self),
                  let accountSecrets = fallbackSecrets[accountID] else {
                continue
            }
            secrets[accountID] = accountSecrets
            try write(secrets)
            return accountSecrets
        }

        return nil
    }

    func save(_ secrets: AccountSecrets, accountID: String) throws {
        var allSecrets = try loadAllSecrets()
        allSecrets[accountID] = secrets
        try write(allSecrets)
    }

    func delete(accountID: String) throws {
        var allSecrets = try loadAllSecrets()
        allSecrets.removeValue(forKey: accountID)
        if allSecrets.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } else {
            try write(allSecrets)
        }
        try delete(accountID: accountID, from: fallbackURLs)
    }

    private func loadAllSecrets() throws -> [String: AccountSecrets] {
        if FileManager.default.fileExists(atPath: url.path) {
            return try LocalEncryptedJSONFile(fileURL: url).load([String: AccountSecrets].self) ?? [:]
        }

        for fallbackURL in fallbackURLs where FileManager.default.fileExists(atPath: fallbackURL.path) {
            guard let secrets = try? LocalEncryptedJSONFile(fileURL: fallbackURL).load([String: AccountSecrets].self),
                  !secrets.isEmpty else {
                continue
            }
            try write(secrets)
            return secrets
        }

        return [:]
    }

    private func write(_ secrets: [String: AccountSecrets]) throws {
        try LocalEncryptedJSONFile(fileURL: url).save(secrets)
    }

    private func delete(accountID: String, from urls: [URL]) throws {
        for fallbackURL in urls where FileManager.default.fileExists(atPath: fallbackURL.path) {
            var secrets = try LocalEncryptedJSONFile(fileURL: fallbackURL).load([String: AccountSecrets].self) ?? [:]
            secrets.removeValue(forKey: accountID)
            if secrets.isEmpty {
                try FileManager.default.removeItem(at: fallbackURL)
            } else {
                try LocalEncryptedJSONFile(fileURL: fallbackURL).save(secrets)
            }
        }
    }
}
