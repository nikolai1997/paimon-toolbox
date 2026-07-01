import XCTest
@testable import PaimonToolbox

final class AccountSecretStoreTests: XCTestCase {
    func testLocalSecretStoreRoundTripsSecrets() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account-secrets.json")
        let store = LocalAccountSecretStore(url: url)
        let secrets = AccountSecrets(
            stuid: "10001",
            stoken: "stoken-value",
            mid: "mid-value",
            cookieToken: "cookie-token",
            ltoken: "ltoken-value"
        )

        try store.save(secrets, accountID: "10001")

        XCTAssertEqual(try store.load(accountID: "10001"), secrets)
    }

    func testLocalSecretStoreEncryptsSecretsOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account-secrets.json")
        let store = LocalAccountSecretStore(url: url)

        try store.save(
            AccountSecrets(
                stuid: "10001",
                stoken: "stoken-secret-value",
                mid: "mid-value",
                cookieToken: "cookie-secret-value",
                ltoken: "ltoken-secret-value"
            ),
            accountID: "10001"
        )

        let rawText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(rawText.contains("stoken-secret-value"))
        XCTAssertFalse(rawText.contains("cookie-secret-value"))
        XCTAssertFalse(rawText.contains("ltoken-secret-value"))
        XCTAssertEqual(try store.load(accountID: "10001")?.stoken, "stoken-secret-value")
    }

    func testLocalSecretStoreMigratesLegacyPlaintextSecretsToEncryptedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account-secrets.json")
        let legacySecrets = [
            "10001": AccountSecrets(
                stuid: "10001",
                stoken: "legacy-stoken-value",
                mid: "mid-value",
                cookieToken: "legacy-cookie-value",
                ltoken: "legacy-ltoken-value"
            )
        ]
        try JSONEncoder().encode(legacySecrets).write(to: url)
        let store = LocalAccountSecretStore(url: url)

        XCTAssertEqual(try store.load(accountID: "10001"), legacySecrets["10001"])

        let migratedText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(migratedText.contains("legacy-stoken-value"))
        XCTAssertFalse(migratedText.contains("legacy-cookie-value"))
        XCTAssertFalse(migratedText.contains("legacy-ltoken-value"))
    }

    func testLocalSecretStoreUsesUserOnlyFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account-secrets.json")
        let store = LocalAccountSecretStore(url: url)

        try store.save(
            AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: nil),
            accountID: "10001"
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600)
    }

    func testLocalSecretStoreDeletesLastSecretFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account-secrets.json")
        let store = LocalAccountSecretStore(url: url)

        try store.save(
            AccountSecrets(stuid: "10001", stoken: "stoken-value", mid: "mid-value", cookieToken: nil, ltoken: nil),
            accountID: "10001"
        )
        try store.delete(accountID: "10001")

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLocalSecretStoreMigratesFromLegacyFallbackURL() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let legacyDirectory = directory.appending(path: "legacy", directoryHint: .isDirectory)
        let currentDirectory = directory.appending(path: "current", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appending(path: "account-secrets.json")
        let currentURL = currentDirectory.appending(path: "account-secrets.json")
        let secrets = AccountSecrets(
            stuid: "10001",
            stoken: "legacy-stoken-value",
            mid: "mid-value",
            cookieToken: "legacy-cookie-value",
            ltoken: "legacy-ltoken-value"
        )
        try LocalAccountSecretStore(url: legacyURL).save(secrets, accountID: "10001")
        let store = LocalAccountSecretStore(url: currentURL, fallbackURLs: [legacyURL])

        XCTAssertEqual(try store.load(accountID: "10001"), secrets)
        XCTAssertEqual(try LocalAccountSecretStore(url: currentURL).load(accountID: "10001"), secrets)
    }

    func testLocalSecretStoreMigratesMatchingLegacySecretWhenPrimaryMissesAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let legacyDirectory = directory.appending(path: "legacy", directoryHint: .isDirectory)
        let currentDirectory = directory.appending(path: "current", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appending(path: "account-secrets.json")
        let currentURL = currentDirectory.appending(path: "account-secrets.json")
        let legacySecrets = AccountSecrets(
            stuid: "10001",
            stoken: "legacy-stoken-value",
            mid: "mid-value",
            cookieToken: "legacy-cookie-value",
            ltoken: "legacy-ltoken-value"
        )
        let currentOnlySecrets = AccountSecrets(
            stuid: "20002",
            stoken: "current-stoken-value",
            mid: "current-mid-value",
            cookieToken: nil,
            ltoken: nil
        )
        try LocalAccountSecretStore(url: legacyURL).save(legacySecrets, accountID: "10001")
        try LocalAccountSecretStore(url: currentURL).save(currentOnlySecrets, accountID: "20002")
        let store = LocalAccountSecretStore(url: currentURL, fallbackURLs: [legacyURL])

        XCTAssertEqual(try store.load(accountID: "10001"), legacySecrets)
        XCTAssertEqual(try LocalAccountSecretStore(url: currentURL).load(accountID: "10001"), legacySecrets)
        XCTAssertEqual(try LocalAccountSecretStore(url: currentURL).load(accountID: "20002"), currentOnlySecrets)
    }
}
