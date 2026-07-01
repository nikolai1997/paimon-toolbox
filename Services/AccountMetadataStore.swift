import Foundation

struct AccountMetadata: Codable, Equatable {
    var account: MiHoYoAccount
    var selectedRole: GenshinRole?
    var lastSummary: SignInSummary?
}

protocol AccountMetadataStoring {
    func load() throws -> AccountMetadata?
    func save(_ metadata: AccountMetadata) throws
    func clear() throws
}

struct LocalAccountMetadataStore: AccountMetadataStoring {
    var url: URL
    private var fallbackURLs: [URL]

    init(url: URL? = nil) throws {
        let resolvedURL = try url ?? AppPaths.accountMetadataURL
        self.url = resolvedURL
        self.fallbackURLs = try [Self.legacyAccountMetadataURL()]
            .filter { $0 != resolvedURL }
    }

    init(url: URL, fallbackURLs: [URL] = []) {
        self.url = url
        self.fallbackURLs = fallbackURLs.filter { $0 != url }
    }

    static func legacyAccountMetadataURL() throws -> URL {
        try AppPaths.legacyAppSupportDirectoryURL().appending(path: "account-metadata.json")
    }

    func load() throws -> AccountMetadata? {
        if FileManager.default.fileExists(atPath: url.path) {
            return try LocalEncryptedJSONFile(fileURL: url).load(AccountMetadata.self)
        }

        for fallbackURL in fallbackURLs where FileManager.default.fileExists(atPath: fallbackURL.path) {
            guard let metadata = try? LocalEncryptedJSONFile(fileURL: fallbackURL).load(AccountMetadata.self) else {
                continue
            }
            try save(metadata)
            return metadata
        }
        return nil
    }

    func save(_ metadata: AccountMetadata) throws {
        try LocalEncryptedJSONFile(fileURL: url).save(metadata)
    }

    func clear() throws {
        for clearURL in [url] + fallbackURLs where FileManager.default.fileExists(atPath: clearURL.path) {
            try FileManager.default.removeItem(at: clearURL)
        }
    }
}
