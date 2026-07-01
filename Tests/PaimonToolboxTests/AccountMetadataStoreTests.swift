import XCTest
@testable import PaimonToolbox

final class AccountMetadataStoreTests: XCTestCase {
    func testRoundTripsAccountState() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LocalAccountMetadataStore(url: directory.appending(path: "account.json"))

        let account = MiHoYoAccount(accountID: "10001", mid: "mid", nickname: "旅行者")
        let role = GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true)
        try store.save(AccountMetadata(account: account, selectedRole: role, lastSummary: nil))

        let loaded = try store.load()
        XCTAssertEqual(loaded?.account, account)
        XCTAssertEqual(loaded?.selectedRole, role)
    }

    func testAccountMetadataIsEncryptedOnDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account.json")
        let store = LocalAccountMetadataStore(url: url)

        try store.save(
            AccountMetadata(
                account: MiHoYoAccount(accountID: "10001", mid: "mid-secret-value", nickname: "旅行者"),
                selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
                lastSummary: nil
            )
        )

        let rawText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(rawText.contains("10001"))
        XCTAssertFalse(rawText.contains("mid-secret-value"))
        XCTAssertFalse(rawText.contains("100000001"))
        XCTAssertEqual(try store.load()?.account.mid, "mid-secret-value")
    }

    func testAccountMetadataMigratesLegacyPlaintextFileToEncryptedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "account.json")
        let metadata = AccountMetadata(
            account: MiHoYoAccount(accountID: "10001", mid: "legacy-mid-value", nickname: "旅行者"),
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            lastSummary: nil
        )
        try JSONEncoder().encode(metadata).write(to: url)
        let store = LocalAccountMetadataStore(url: url)

        XCTAssertEqual(try store.load(), metadata)

        let migratedText = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertFalse(migratedText.contains("legacy-mid-value"))
        XCTAssertFalse(migratedText.contains("100000001"))
    }

    func testAccountMetadataMigratesFromLegacyFallbackURL() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let legacyDirectory = directory.appending(path: "legacy", directoryHint: .isDirectory)
        let currentDirectory = directory.appending(path: "current", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        let legacyURL = legacyDirectory.appending(path: "account-metadata.json")
        let currentURL = currentDirectory.appending(path: "account-metadata.json")
        let metadata = AccountMetadata(
            account: MiHoYoAccount(accountID: "10001", mid: "legacy-mid-value", nickname: "旅行者"),
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            lastSummary: nil
        )
        try LocalAccountMetadataStore(url: legacyURL).save(metadata)
        let store = LocalAccountMetadataStore(url: currentURL, fallbackURLs: [legacyURL])

        XCTAssertEqual(try store.load(), metadata)
        XCTAssertEqual(try LocalAccountMetadataStore(url: currentURL).load(), metadata)
    }
}
