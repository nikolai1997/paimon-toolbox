import XCTest
@testable import PaimonToolbox

@MainActor
final class RemoteMetadataRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: RemoteDataSettings.lastAutoRefreshAttemptKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: RemoteDataSettings.lastAutoRefreshAttemptKey)
        super.tearDown()
    }

    func testLoadAutomaticallyRefreshesFromConfiguredRemoteMetadataURL() async {
        let local = makeMetadata(version: "local")
        let remote = makeMetadata(version: "remote")
        let service = MockMetadataService(local: local, remote: remote)
        let overviewService = MockOverviewDataService(
            results: [
                makeOverviewData(eventName: "旧卡池"),
                makeOverviewData(eventName: "新卡池")
            ]
        )
        let store = makeStore(metadataService: service, overviewDataService: overviewService)

        await store.load(
            remoteMetadataURLString: "https://example.com/metadata.json",
            offlinePackageURLString: "",
            autoRefreshRemoteMetadata: true
        )

        XCTAssertEqual(store.metadata, remote)
        XCTAssertEqual(service.refreshedURL?.absoluteString, "https://example.com/metadata.json")
        XCTAssertEqual(store.successMessage, "资料库已自动从 GitHub 更新")
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(overviewService.loadCount, 2)
        XCTAssertEqual(store.overviewData.gachaEvents.first?.name, "新卡池")
    }

    func testAutomaticRemoteRefreshRunsAtMostOncePerDay() async {
        let local = makeMetadata(version: "local")
        let remote = makeMetadata(version: "remote")
        let service = MockMetadataService(local: local, remote: remote)
        let store = makeStore(metadataService: service)

        await store.load(
            remoteMetadataURLString: "https://example.com/metadata.json",
            offlinePackageURLString: "",
            autoRefreshRemoteMetadata: true,
            now: Date(timeIntervalSince1970: 1_788_480_000)
        )
        await store.load(
            remoteMetadataURLString: "https://example.com/metadata.json",
            offlinePackageURLString: "",
            autoRefreshRemoteMetadata: true,
            now: Date(timeIntervalSince1970: 1_788_483_600)
        )

        XCTAssertEqual(service.refreshCallCount, 1)

        await store.load(
            remoteMetadataURLString: "https://example.com/metadata.json",
            offlinePackageURLString: "",
            autoRefreshRemoteMetadata: true,
            now: Date(timeIntervalSince1970: 1_788_566_401)
        )

        XCTAssertEqual(service.refreshCallCount, 2)
    }

    func testImportingOfflinePackageReloadsOverviewDataFromPublicCache() async {
        let local = makeMetadata(version: "local")
        let remote = makeMetadata(version: "remote")
        let service = MockMetadataService(local: local, remote: remote)
        let overviewService = MockOverviewDataService(
            results: [
                makeOverviewData(eventName: "离线包卡池")
            ]
        )
        let store = makeStore(metadataService: service, overviewDataService: overviewService)

        await store.importMetadataPackage(from: URL(fileURLWithPath: "/tmp/data-pack.zip"))

        XCTAssertEqual(store.metadata, remote)
        XCTAssertEqual(store.successMessage, "已导入离线资料库")
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(overviewService.loadCount, 1)
        XCTAssertEqual(store.overviewData.gachaEvents.first?.name, "离线包卡池")
    }

    func testLoadKeepsLocalMetadataAndShowsOfflinePackagePromptWhenRemoteRefreshFails() async {
        let local = makeMetadata(version: "local")
        let service = MockMetadataService(local: local, remote: makeMetadata(version: "remote"))
        service.refreshError = MetadataRefreshError.badStatus(503)
        let store = makeStore(metadataService: service)

        await store.load(
            remoteMetadataURLString: "https://example.com/metadata.json",
            offlinePackageURLString: "https://pan.example.com/data-pack.zip",
            autoRefreshRemoteMetadata: true
        )

        XCTAssertEqual(store.metadata, local)
        XCTAssertTrue(store.errorMessage?.contains("GitHub 数据更新失败") == true)
        XCTAssertTrue(store.errorMessage?.contains("https://pan.example.com/data-pack.zip") == true)
    }

    private func makeMetadata(version: String) -> MetadataBundle {
        MetadataBundle(
            version: version,
            updatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            characters: [],
            weapons: [],
            materials: []
        )
    }

    private func makeOverviewData(eventName: String) -> OverviewData {
        OverviewData(
            latest: nil,
            announcements: [],
            gachaEvents: [
                GachaEventInfo(
                    name: eventName,
                    type: 301,
                    version: "6.6",
                    from: Date(timeIntervalSince1970: 1_782_700_800),
                    to: Date(timeIntervalSince1970: 1_783_564_800),
                    bannerURL: nil,
                    upOrangeList: [],
                    upPurpleList: []
                )
            ]
        )
    }

    private func makeStore(
        metadataService: MetadataServicing,
        overviewDataService: OverviewDataServicing = MockOverviewDataService(results: [.empty])
    ) -> AppStore {
        AppStore(
            metadataService: metadataService,
            overviewDataService: overviewDataService,
            gachaService: EmptyGachaService(),
            plannerService: EmptyPlannerService(),
            accountService: EmptyAccountSessionService(),
            widgetSnapshotStore: InMemoryWidgetSnapshotStore()
        )
    }
}

@MainActor
private final class MockMetadataService: MetadataServicing {
    let local: MetadataBundle
    let remote: MetadataBundle
    var refreshedURL: URL?
    var refreshError: Error?
    private(set) var refreshCallCount = 0

    init(local: MetadataBundle, remote: MetadataBundle) {
        self.local = local
        self.remote = remote
    }

    func loadMetadata() async throws -> MetadataBundle {
        local
    }

    func refreshMetadata(from url: URL) async throws -> MetadataBundle {
        refreshCallCount += 1
        refreshedURL = url
        if let refreshError {
            throw refreshError
        }
        return remote
    }

    func importMetadataPackage(from url: URL) async throws -> MetadataBundle {
        remote
    }
}

@MainActor
private final class MockOverviewDataService: OverviewDataServicing {
    private var results: [OverviewData]
    private(set) var loadCount = 0

    init(results: [OverviewData]) {
        self.results = results
    }

    func loadOverviewData() async throws -> OverviewData {
        defer { loadCount += 1 }
        guard !results.isEmpty else {
            return .empty
        }
        return results.removeFirst()
    }
}

@MainActor
private final class EmptyGachaService: GachaLogServicing {
    func loadRecords() async throws -> [GachaRecord] { [] }
    func importRecords(from url: URL, into existing: [GachaRecord]) async throws -> [GachaRecord] { existing }
    func exportRecords(_ records: [GachaRecord], to url: URL) async throws {}
    func replaceRecords(_ records: [GachaRecord]) async throws {}
    func summary(for records: [GachaRecord]) -> GachaSummary {
        GachaSummary(totalPulls: 0, fiveStarCount: 0, fourStarCount: 0, pitySinceLastFiveStar: 0)
    }
}

@MainActor
private final class EmptyPlannerService: PlannerServicing {
    func loadPlans() async throws -> [CultivationPlan] { [] }
    func savePlans(_ plans: [CultivationPlan]) async throws {}
}

@MainActor
private final class EmptyAccountSessionService: AccountSessionServicing {
    func loadStatus() -> LocalAccountStatus { .signedOut }
    func startQrLogin() async throws -> QrLoginSession { throw AccountSessionError.missingAccount }
    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload { throw AccountSessionError.missingAccount }
    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func refreshSignInStatus() async throws -> LocalAccountStatus { .signedOut }
    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func loadResignInfo() async throws -> SignInResignInfoPayload { throw AccountSessionError.missingAccount }
    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func signInWebVerificationContext() throws -> SignInWebVerificationContext { throw AccountSessionError.missingAccount }
    func refreshLoginTokens() async throws -> LocalAccountStatus { .signedOut }
    func loadGachaRecords() async throws -> [GachaRecord] { [] }
    func signOut() throws -> LocalAccountStatus { .signedOut }
}

private final class InMemoryWidgetSnapshotStore: WidgetSnapshotStoring {
    private var snapshot: WidgetSnapshot = .empty

    func load() throws -> WidgetSnapshot {
        snapshot
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        self.snapshot = snapshot
    }
}
