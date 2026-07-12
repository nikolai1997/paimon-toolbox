import XCTest
@testable import PaimonToolbox

@MainActor
final class GachaLogServiceTests: XCTestCase {
    func testNewGachaStoreStartsEmptyInsteadOfSampleRecords() async throws {
        let userDefaults = try makeUserDefaults()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = LocalGachaLogService(
            recordsURL: directory.appending(path: "gacha-records.json"),
            legacyRecordURLs: [],
            userDefaults: userDefaults
        )

        let records = try await service.loadRecords()

        XCTAssertEqual(records, [])
    }

    func testLocalGachaStoreLoadsRecordsSavedByPreviousInstance() async throws {
        let userDefaults = try makeUserDefaults()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "gacha-records.json")
        let saved = [
            GachaRecord(
                id: "persisted",
                time: Date(timeIntervalSince1970: 2),
                banner: .character,
                name: "芙宁娜",
                itemType: "角色",
                rarity: 5
            )
        ]

        let writer = LocalGachaLogService(recordsURL: url, legacyRecordURLs: [], userDefaults: userDefaults)
        try await writer.replaceRecords(saved)
        let reader = LocalGachaLogService(recordsURL: url, legacyRecordURLs: [], userDefaults: userDefaults)

        let loaded = try await reader.loadRecords()

        XCTAssertEqual(loaded, saved)
    }

    func testLocalGachaStoreMigratesRecordsFromLegacyLocationWhenPrimaryIsEmpty() async throws {
        let userDefaults = try makeUserDefaults()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appending(path: "gacha-records.json")
        let legacyURL = directory.appending(path: "legacy-gacha-records.json")
        let legacy = [
            GachaRecord(
                id: "legacy",
                time: Date(timeIntervalSince1970: 4),
                banner: .character,
                name: "娜维娅",
                itemType: "角色",
                rarity: 5
            )
        ]

        try await LocalGachaLogService(recordsURL: legacyURL, legacyRecordURLs: [], userDefaults: userDefaults).replaceRecords(legacy)
        try await LocalGachaLogService(recordsURL: primaryURL, legacyRecordURLs: [], userDefaults: userDefaults).replaceRecords([])

        let service = LocalGachaLogService(recordsURL: primaryURL, legacyRecordURLs: [legacyURL], userDefaults: userDefaults)
        let loaded = try await service.loadRecords()
        let reloaded = try await LocalGachaLogService(recordsURL: primaryURL, legacyRecordURLs: [], userDefaults: userDefaults).loadRecords()

        XCTAssertEqual(loaded, legacy)
        XCTAssertEqual(reloaded, legacy)
    }

    func testLocalGachaStoreLoadsMirroredRecordsWhenFilesAreUnavailable() async throws {
        let suiteName = "GachaLogServiceTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "gacha-records.json")
        let saved = [
            GachaRecord(
                id: "mirrored",
                time: Date(timeIntervalSince1970: 5),
                banner: .weapon,
                name: "雾切之回光",
                itemType: "武器",
                rarity: 5
            )
        ]

        let writer = LocalGachaLogService(recordsURL: missingURL, legacyRecordURLs: [], userDefaults: userDefaults)
        try await writer.replaceRecords(saved)
        try? FileManager.default.removeItem(at: missingURL)

        let reader = LocalGachaLogService(recordsURL: missingURL, legacyRecordURLs: [], userDefaults: userDefaults)
        let loaded = try await reader.loadRecords()

        XCTAssertEqual(loaded, saved)
    }

    func testFailedPrimaryWriteDoesNotPublishRecordsToMirror() async throws {
        let userDefaults = try makeUserDefaults()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedParent = directory.appending(path: "not-a-directory")
        try Data("blocked".utf8).write(to: blockedParent)
        let recordsURL = blockedParent.appending(path: "gacha-records.json")
        let service = LocalGachaLogService(recordsURL: recordsURL, legacyRecordURLs: [], userDefaults: userDefaults)
        let record = GachaRecord(
            id: "must-not-survive",
            time: Date(timeIntervalSince1970: 5),
            banner: .character,
            name: "测试记录",
            itemType: "角色",
            rarity: 5
        )

        do {
            try await service.replaceRecords([record])
            XCTFail("Expected the primary write to fail")
        } catch {
            let reloaded = try await service.loadRecords()
            XCTAssertEqual(reloaded, [])
        }
    }

    func testLegacyUIGFImportPreservesCharacterEventTwoAndChronicledTypes() throws {
        let data = """
        {
          "info": {
            "uid": "100000001",
            "lang": "zh-cn",
            "export_time": "2026-06-24 12:00:00",
            "export_timestamp": 1782273600,
            "uigf_version": "v3.0"
          },
          "list": [
            {
              "id": "400-1",
              "time": "2026-06-24 12:01:00",
              "name": "浪涌之瞬",
              "item_type": "角色",
              "rank_type": "5",
              "gacha_type": "400",
              "uigf_gacha_type": "301"
            },
            {
              "id": "500-1",
              "time": "2026-06-24 12:02:00",
              "name": "晨风之诗",
              "item_type": "角色",
              "rank_type": "5",
              "gacha_type": "500",
              "uigf_gacha_type": "500"
            }
          ]
        }
        """.data(using: .utf8)!

        let records = try GachaLogDocument.decodeRecords(from: data)

        XCTAssertEqual(records.map(\.banner.rawValue), ["chronicled", "characterEvent2"])
        XCTAssertEqual(records.map(\.uid), ["100000001", "100000001"])

    }

    func testUIGFV4ImportAndCurrentAccountExportUsesAccountContainerAndSharedPityType() throws {
        let data = """
        {
          "info": {
            "export_timestamp": 1782273600,
            "export_app": "测试工具",
            "export_app_version": "1.0",
            "version": "v4.0"
          },
          "hk4e": [
            {
              "uid": "100000001",
              "timezone": 8,
              "lang": "zh-cn",
              "list": [
                {
                  "id": "4001",
                  "item_id": "10000099",
                  "time": "2026-06-24 12:01:00",
                  "name": "浪涌之瞬",
                  "item_type": "角色",
                  "rank_type": "5",
                  "gacha_type": "400",
                  "uigf_gacha_type": "301"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let records = try GachaLogDocument.decodeRecords(from: data)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].uid, "100000001")
        XCTAssertEqual(records[0].itemID, "10000099")
        XCTAssertEqual(records[0].banner, .characterEvent2)

        let exported = try GachaLogDocument.encodeUIGFRecords(records, appVersion: "9.8.7")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let info = try XCTUnwrap(json["info"] as? [String: Any])
        XCTAssertEqual(info["version"] as? String, "v4.0")
        XCTAssertEqual(info["export_app_version"] as? String, "9.8.7")
        XCTAssertNil(info["uigf_version"])
        let accounts = try XCTUnwrap(json["hk4e"] as? [[String: Any]])
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0]["uid"] as? String, "100000001")
        XCTAssertEqual(accounts[0]["timezone"] as? Int, 8)
        let list = try XCTUnwrap(accounts[0]["list"] as? [[String: Any]])
        XCTAssertEqual(list[0]["gacha_type"] as? String, "400")
        XCTAssertEqual(list[0]["uigf_gacha_type"] as? String, "301")
        XCTAssertEqual(list[0]["item_id"] as? String, "10000099")
    }

    func testGachaExportIsExplicitlyScopedToCurrentAccount() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Views/GachaLogView.swift"),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: projectRoot.appendingPathComponent("Stores/AppStore.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(viewSource.contains("Label(\"导出当前账号 UIGF\""))
        XCTAssertTrue(storeSource.contains("gachaService.exportRecords(activeGachaRecords"))
        XCTAssertTrue(storeSource.contains("successMessage = \"已导出当前账号 UIGF 文件\""))
    }

    func testMergeDoesNotOverwriteSameRecordIDFromDifferentUIDs() {
        let first = GachaRecord(
            uid: "1001",
            id: "same-id",
            time: Date(timeIntervalSince1970: 1),
            banner: .character,
            name: "账号一",
            itemType: "角色",
            rarity: 5
        )
        let second = GachaRecord(
            uid: "1002",
            id: "same-id",
            time: Date(timeIntervalSince1970: 2),
            banner: .character,
            name: "账号二",
            itemType: "角色",
            rarity: 5
        )

        let merged = GachaLogDocument.mergedRecords(existing: [first], imported: [second])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.compactMap(\.uid)), ["1001", "1002"])
    }

    func testSignedOutStoreCanSelectBetweenMultipleImportedUIDs() {
        let first = GachaRecord(
            uid: "1001",
            id: "1",
            time: Date(timeIntervalSince1970: 1),
            banner: .character,
            name: "账号一",
            itemType: "角色",
            rarity: 5
        )
        let second = GachaRecord(
            uid: "1002",
            id: "2",
            time: Date(timeIntervalSince1970: 2),
            banner: .standard,
            name: "账号二",
            itemType: "角色",
            rarity: 5
        )
        let store = AppStore()
        store.gachaRecords = [first, second]

        store.selectGachaUID("1002")

        XCTAssertEqual(store.availableGachaUIDs, ["1001", "1002"])
        XCTAssertEqual(store.activeGachaRecords.map(\.name), ["账号二"])
        XCTAssertEqual(store.gachaSummary.totalPulls, 1)
    }

    func testSigningOutKeepsMostRecentAccountUIDSelected() {
        let first = GachaRecord(uid: "1001", id: "1", time: Date(timeIntervalSince1970: 1), banner: .character, name: "账号一", itemType: "角色", rarity: 5)
        let second = GachaRecord(uid: "1002", id: "2", time: Date(timeIntervalSince1970: 2), banner: .standard, name: "账号二", itemType: "角色", rarity: 5)
        let store = AppStore()
        store.gachaRecords = [first, second]
        store.selectGachaUID("1001")
        store.accountStatus = LocalAccountStatus(
            isSignedIn: true,
            nickname: "旅行者",
            accountID: "account",
            selectedRole: GenshinRole(uid: "1002", region: "cn_gf01", nickname: "荧", level: 60, isSelected: true),
            signInSummary: nil,
            sessionMessage: nil,
            lastCheckInDate: nil
        )

        store.accountStatus = .signedOut

        XCTAssertEqual(store.activeGachaUID, "1002")
        XCTAssertEqual(store.activeGachaRecords.map(\.name), ["账号二"])
    }

    func testLegacyNativeRecordWithoutUIDRemainsUnassigned() throws {
        let data = """
        [
          {
            "id": "legacy",
            "time": "2026-06-24T04:00:00Z",
            "banner": "standard",
            "name": "冷刃",
            "itemType": "武器",
            "rarity": 3
          }
        ]
        """.data(using: .utf8)!

        let records = try GachaLogDocument.decodeRecords(from: data)

        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records[0].uid)
    }

    func testAppStoreLoadKeepsCachedGachaRecordsWhenMetadataLoadFails() async throws {
        let cached = [
            GachaRecord(
                id: "cached",
                time: Date(timeIntervalSince1970: 3),
                banner: .weapon,
                name: "祭礼弓",
                itemType: "武器",
                rarity: 4
            )
        ]
        let store = AppStore(
            metadataService: FailingMetadataService(),
            gachaService: InMemoryGachaService(records: cached),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: GachaSyncAccountService(records: [])
        )

        await store.load(autoRefreshRemoteMetadata: false)

        XCTAssertEqual(store.gachaRecords, cached)
        XCTAssertEqual(store.gachaSummary.totalPulls, 1)
        XCTAssertEqual(store.errorMessage, "资料库加载失败：fixture metadata failure")
    }

    func testAppStoreSyncsGachaRecordsFromSignedInAccountAndPersistsMerge() async throws {
        let existing = GachaRecord(
            id: "old",
            time: Date(timeIntervalSince1970: 1),
            banner: .standard,
            name: "冷刃",
            itemType: "武器",
            rarity: 3
        )
        let remote = GachaRecord(
            id: "new",
            time: Date(timeIntervalSince1970: 2),
            banner: .character,
            name: "莉奈娅",
            itemType: "角色",
            rarity: 5
        )
        let gachaService = InMemoryGachaService(records: [existing])
        let accountService = GachaSyncAccountService(records: [remote])
        let store = AppStore(gachaService: gachaService, accountService: accountService)
        store.gachaRecords = [existing]
        store.gachaSummary = gachaService.summary(for: [existing])

        await store.syncGachaRecordsFromAccount()

        XCTAssertEqual(store.gachaRecords.map(\.id), ["new", "old"])
        XCTAssertEqual(gachaService.savedRecords.map(\.id), ["new", "old"])
        XCTAssertEqual(store.successMessage, "已从账号更新 1 条祈愿记录，当前共 2 条")
        XCTAssertNil(store.errorMessage)
    }

    func testSignedInAccountSummaryDoesNotMixRecordsFromAnotherUID() async throws {
        let otherAccount = GachaRecord(
            uid: "2002",
            id: "shared-id",
            time: Date(timeIntervalSince1970: 1),
            banner: .standard,
            name: "另一个账号",
            itemType: "角色",
            rarity: 5
        )
        let currentAccount = GachaRecord(
            id: "shared-id",
            time: Date(timeIntervalSince1970: 2),
            banner: .character,
            name: "当前账号",
            itemType: "角色",
            rarity: 5
        )
        let status = LocalAccountStatus(
            isSignedIn: true,
            nickname: "旅行者",
            accountID: "account",
            selectedRole: GenshinRole(uid: "1001", region: "cn_gf01", nickname: "荧", level: 60, isSelected: true),
            signInSummary: nil,
            sessionMessage: nil,
            lastCheckInDate: nil
        )
        let gachaService = InMemoryGachaService(records: [otherAccount])
        let accountService = GachaSyncAccountService(records: [currentAccount], status: status)
        let store = AppStore(gachaService: gachaService, accountService: accountService)
        store.gachaRecords = [otherAccount]
        store.accountStatus = status

        await store.syncGachaRecordsFromAccount()

        XCTAssertEqual(store.gachaRecords.count, 2)
        XCTAssertEqual(store.activeGachaRecords.map(\.uid), ["1001"])
        XCTAssertEqual(store.gachaSummary.totalPulls, 1)
        XCTAssertEqual(store.activeGachaRecords.first?.name, "当前账号")
    }

    private func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "GachaLogServiceTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}

private struct FailingMetadataService: MetadataServicing {
    func loadMetadata() async throws -> MetadataBundle {
        throw MetadataFixtureError.failure
    }

    func refreshMetadata(from url: URL) async throws -> MetadataBundle {
        throw MetadataFixtureError.failure
    }

    func importMetadataPackage(from url: URL) async throws -> MetadataBundle {
        throw MetadataFixtureError.failure
    }
}

private enum MetadataFixtureError: Error, LocalizedError {
    case failure

    var errorDescription: String? {
        "fixture metadata failure"
    }
}

@MainActor
private final class InMemoryPlannerService: PlannerServicing {
    var plans: [CultivationPlan]

    init(plans: [CultivationPlan]) {
        self.plans = plans
    }

    func loadPlans() async throws -> [CultivationPlan] {
        plans
    }

    func savePlans(_ plans: [CultivationPlan]) async throws {
        self.plans = plans
    }
}

@MainActor
private final class InMemoryGachaService: GachaLogServicing {
    var records: [GachaRecord]
    var savedRecords: [GachaRecord] = []

    init(records: [GachaRecord]) {
        self.records = records
    }

    func loadRecords() async throws -> [GachaRecord] { records }

    func importRecords(from url: URL, into existing: [GachaRecord]) async throws -> [GachaRecord] { existing }

    func exportRecords(_ records: [GachaRecord], to url: URL) async throws {}

    func replaceRecords(_ records: [GachaRecord]) async throws {
        savedRecords = records
        self.records = records
    }

    func summary(for records: [GachaRecord]) -> GachaSummary {
        GachaSummary.make(from: records)
    }
}

@MainActor
private final class GachaSyncAccountService: AccountSessionServicing {
    var records: [GachaRecord]
    var status: LocalAccountStatus

    init(records: [GachaRecord], status: LocalAccountStatus = .signedOut) {
        self.records = records
        self.status = status
    }

    func loadStatus() -> LocalAccountStatus { status }
    func startQrLogin() async throws -> QrLoginSession { throw AccountSessionError.missingAccount }
    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload { throw AccountSessionError.missingAccount }
    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func refreshSignInStatus() async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func loadResignInfo() async throws -> SignInResignInfoPayload { throw AccountSessionError.missingAccount }
    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func signInWebVerificationContext() throws -> SignInWebVerificationContext { throw AccountSessionError.missingAccount }
    func refreshLoginTokens() async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func loadGachaRecords() async throws -> [GachaRecord] { records }
    func signOut() throws -> LocalAccountStatus { .signedOut }
}
