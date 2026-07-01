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

    func testUIGFImportAndExportPreservesCharacterEventTwoAndChronicledTypes() throws {
        let data = """
        {
          "info": {
            "uid": "100000001",
            "lang": "zh-cn",
            "export_time": "2026-06-24 12:00:00",
            "export_timestamp": 1782273600,
            "uigf_version": "v4.0"
          },
          "list": [
            {
              "id": "400-1",
              "time": "2026-06-24 12:01:00",
              "name": "浪涌之瞬",
              "item_type": "角色",
              "rank_type": "5",
              "gacha_type": "400",
              "uigf_gacha_type": "400"
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

        XCTAssertEqual(records.map(\.banner.rawValue), ["characterEvent2", "chronicled"])

        let exported = try GachaLogDocument.encodeUIGFRecords(records)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let list = try XCTUnwrap(json["list"] as? [[String: Any]])
        XCTAssertEqual(list.compactMap { $0["uigf_gacha_type"] as? String }.sorted(), ["400", "500"])
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

    init(records: [GachaRecord]) {
        self.records = records
    }

    func loadStatus() -> LocalAccountStatus { .signedOut }
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
