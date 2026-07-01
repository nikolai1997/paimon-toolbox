import XCTest
@testable import PaimonToolbox

@MainActor
final class WidgetSnapshotPublishingTests: XCTestCase {
    func testLoadPublishesWidgetSnapshotFromLoadedAppState() async {
        let gachaRecords = [
            GachaRecord(
                id: "1",
                time: Date(timeIntervalSince1970: 20),
                banner: .character,
                name: "神里绫华",
                itemType: "角色",
                rarity: 5
            )
        ]
        let widgetStore = InMemoryWidgetSnapshotStore()
        let widgetReloader = InMemoryWidgetTimelineReloader()
        let store = AppStore(
            metadataService: EmptyMetadataService(),
            overviewDataService: EmptyOverviewDataService(),
            gachaService: InMemoryGachaService(records: gachaRecords),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: EmptyAccountSessionService(status: .signedOut),
            autoSignInStore: InMemoryAutoSignInStore(),
            widgetSnapshotStore: widgetStore,
            widgetTimelineReloader: widgetReloader
        )

        await store.load(autoRefreshRemoteMetadata: false, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(widgetStore.savedSnapshots.count, 1)
        XCTAssertEqual(widgetReloader.reloadedKinds, [PaimonToolboxWidgetConfiguration.kind])
        XCTAssertEqual(widgetStore.savedSnapshots.first?.gacha.totalPulls, 1)
        XCTAssertEqual(store.widgetSnapshot.gacha.lastFiveStarName, "神里绫华")
    }

    func testWidgetSaveFailureDoesNotReplaceSuccessfulUserFlowMessages() async {
        let importedRecords = [
            GachaRecord(
                id: "1",
                time: Date(timeIntervalSince1970: 20),
                banner: .character,
                name: "神里绫华",
                itemType: "角色",
                rarity: 5
            )
        ]
        let widgetReloader = InMemoryWidgetTimelineReloader()
        let store = AppStore(
            metadataService: EmptyMetadataService(),
            overviewDataService: EmptyOverviewDataService(),
            gachaService: InMemoryGachaService(records: [], importedRecords: importedRecords),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: EmptyAccountSessionService(status: .signedOut),
            autoSignInStore: InMemoryAutoSignInStore(),
            widgetSnapshotStore: ThrowingWidgetSnapshotStore(),
            widgetTimelineReloader: widgetReloader
        )

        await store.importGachaRecords(from: URL(fileURLWithPath: "/tmp/gacha.json"))

        XCTAssertEqual(store.successMessage, "已导入并合并 1 条祈愿记录")
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(widgetReloader.reloadedKinds.isEmpty)
        XCTAssertEqual(store.widgetSnapshot.gacha.lastFiveStarName, "神里绫华")
    }

    func testLoadWithAutoSignInPublishesOneWidgetSnapshot() async {
        let widgetStore = InMemoryWidgetSnapshotStore()
        let widgetReloader = InMemoryWidgetTimelineReloader()
        let autoSignInStore = InMemoryAutoSignInStore(isEnabled: true)
        let now = Date(timeIntervalSince1970: 100)
        autoSignInStore.setScheduledAttemptDate(
            Date(timeIntervalSince1970: 0),
            accountID: "10001",
            uid: "100000001",
            serverDay: "cn_gf01:1970-01-01"
        )
        let accountService = AutoSignInAccountSessionService(
            initialStatus: Self.signedInStatus(isTodaySigned: false),
            refreshedStatus: Self.signedInStatus(isTodaySigned: false),
            claimedStatus: Self.signedInStatus(isTodaySigned: true)
        )
        let store = AppStore(
            metadataService: EmptyMetadataService(),
            overviewDataService: EmptyOverviewDataService(),
            gachaService: InMemoryGachaService(records: []),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: accountService,
            autoSignInStore: autoSignInStore,
            widgetSnapshotStore: widgetStore,
            widgetTimelineReloader: widgetReloader
        )

        await store.load(autoRefreshRemoteMetadata: false, now: now)

        XCTAssertEqual(widgetStore.savedSnapshots.count, 1)
        XCTAssertEqual(widgetReloader.reloadedKinds, [PaimonToolboxWidgetConfiguration.kind])
        XCTAssertTrue(widgetStore.savedSnapshots.first?.signIn.isTodaySigned == true)
        XCTAssertEqual(accountService.claimDailyRewardCallCount, 1)
    }

    func testLoadDoesNotOverwriteMigratedUsefulWidgetSnapshotWithEmptyState() async {
        let widgetStore = InMemoryWidgetSnapshotStore()
        widgetStore.snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_780_000_200),
            signIn: WidgetSignInSnapshot(
                isSignedIn: true,
                nickname: "我爱老登",
                uid: "110209152",
                isTodaySigned: true,
                totalSignDay: 26,
                statusText: "已签到",
                actionTitle: "查看账号",
                message: nil
            ),
            gacha: WidgetGachaSnapshot(
                totalPulls: 938,
                fiveStarCount: 17,
                fourStarCount: 118,
                pitySinceLastFiveStar: 3,
                lastFiveStarName: "梦见月瑞希",
                lastFiveStarDate: nil,
                characterPulls: 761,
                weaponPulls: 0,
                standardPulls: 177
            ),
            planner: .empty
        )
        let widgetReloader = InMemoryWidgetTimelineReloader()
        let store = AppStore(
            metadataService: EmptyMetadataService(),
            overviewDataService: EmptyOverviewDataService(),
            gachaService: InMemoryGachaService(records: []),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: EmptyAccountSessionService(status: .signedOut),
            autoSignInStore: InMemoryAutoSignInStore(),
            widgetSnapshotStore: widgetStore,
            widgetTimelineReloader: widgetReloader
        )

        await store.load(autoRefreshRemoteMetadata: false, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(widgetStore.savedSnapshots.last?.signIn.nickname, "我爱老登")
        XCTAssertEqual(widgetStore.savedSnapshots.last?.gacha.totalPulls, 938)
        XCTAssertEqual(store.widgetSnapshot.signIn.nickname, "我爱老登")
    }

    func testWidgetRefreshDeepLinkRefreshesStatusAndPublishesSnapshot() async {
        let widgetStore = InMemoryWidgetSnapshotStore()
        let widgetReloader = InMemoryWidgetTimelineReloader()
        let accountService = RefreshableAccountSessionService(
            initialStatus: Self.signedInStatus(isTodaySigned: false),
            refreshedStatus: Self.signedInStatus(isTodaySigned: true)
        )
        let store = AppStore(
            metadataService: EmptyMetadataService(),
            overviewDataService: EmptyOverviewDataService(),
            gachaService: InMemoryGachaService(records: []),
            plannerService: InMemoryPlannerService(plans: []),
            accountService: accountService,
            autoSignInStore: InMemoryAutoSignInStore(),
            widgetSnapshotStore: widgetStore,
            widgetTimelineReloader: widgetReloader
        )

        store.routeDeepLink(URL(string: "paimontoolbox://widget/refresh")!)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.selectedSection, .overview)
        XCTAssertEqual(accountService.refreshSignInStatusCallCount, 1)
        XCTAssertEqual(widgetStore.savedSnapshots.last?.signIn.statusText, "已签到")
        XCTAssertEqual(widgetReloader.reloadedKinds.last, PaimonToolboxWidgetConfiguration.kind)
    }

    private static func signedInStatus(isTodaySigned: Bool) -> LocalAccountStatus {
        LocalAccountStatus(
            isSignedIn: true,
            nickname: "旅行者",
            accountID: "10001",
            selectedRole: GenshinRole(uid: "100000001", region: "cn_gf01", nickname: "空", level: 60, isSelected: true),
            signInSummary: SignInSummary(uid: "100000001", month: 9, totalSignDay: isTodaySigned ? 3 : 2, isTodaySigned: isTodaySigned, rewards: []),
            sessionMessage: nil,
            lastCheckInDate: nil
        )
    }
}

@MainActor
private final class RefreshableAccountSessionService: AccountSessionServicing {
    var initialStatus: LocalAccountStatus
    var refreshedStatus: LocalAccountStatus
    private(set) var refreshSignInStatusCallCount = 0

    init(initialStatus: LocalAccountStatus, refreshedStatus: LocalAccountStatus) {
        self.initialStatus = initialStatus
        self.refreshedStatus = refreshedStatus
    }

    func loadStatus() -> LocalAccountStatus { initialStatus }
    func startQrLogin() async throws -> QrLoginSession { throw AccountSessionError.missingAccount }
    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload { throw AccountSessionError.missingAccount }
    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func refreshSignInStatus() async throws -> LocalAccountStatus {
        refreshSignInStatusCallCount += 1
        return refreshedStatus
    }
    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func loadResignInfo() async throws -> SignInResignInfoPayload { throw AccountSessionError.missingAccount }
    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func signInWebVerificationContext() throws -> SignInWebVerificationContext { throw AccountSessionError.missingAccount }
    func refreshLoginTokens() async throws -> LocalAccountStatus { refreshedStatus }
    func loadGachaRecords() async throws -> [GachaRecord] { [] }
    func signOut() throws -> LocalAccountStatus { .signedOut }
}

@MainActor
private struct EmptyMetadataService: MetadataServicing {
    func loadMetadata() async throws -> MetadataBundle {
        MetadataBundle(
            version: "test",
            updatedAt: Date(timeIntervalSince1970: 0),
            characters: [],
            weapons: [],
            materials: []
        )
    }

    func refreshMetadata(from url: URL) async throws -> MetadataBundle {
        try await loadMetadata()
    }

    func importMetadataPackage(from url: URL) async throws -> MetadataBundle {
        try await loadMetadata()
    }
}

@MainActor
private struct EmptyOverviewDataService: OverviewDataServicing {
    func loadOverviewData() async throws -> OverviewData {
        .empty
    }
}

@MainActor
private final class InMemoryGachaService: GachaLogServicing {
    var records: [GachaRecord]
    var importedRecords: [GachaRecord]?

    init(records: [GachaRecord], importedRecords: [GachaRecord]? = nil) {
        self.records = records
        self.importedRecords = importedRecords
    }

    func loadRecords() async throws -> [GachaRecord] {
        records
    }

    func importRecords(from url: URL, into existing: [GachaRecord]) async throws -> [GachaRecord] {
        let imported = importedRecords ?? existing
        records = imported
        return imported
    }

    func exportRecords(_ records: [GachaRecord], to url: URL) async throws {}

    func replaceRecords(_ records: [GachaRecord]) async throws {
        self.records = records
    }

    func summary(for records: [GachaRecord]) -> GachaSummary {
        GachaSummary.make(from: records)
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
private final class EmptyAccountSessionService: AccountSessionServicing {
    var status: LocalAccountStatus

    init(status: LocalAccountStatus) {
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
    func loadGachaRecords() async throws -> [GachaRecord] { [] }
    func signOut() throws -> LocalAccountStatus {
        status = .signedOut
        return status
    }
}

@MainActor
private final class AutoSignInAccountSessionService: AccountSessionServicing {
    var initialStatus: LocalAccountStatus
    var refreshedStatus: LocalAccountStatus
    var claimedStatus: LocalAccountStatus
    private(set) var claimDailyRewardCallCount = 0

    init(initialStatus: LocalAccountStatus, refreshedStatus: LocalAccountStatus, claimedStatus: LocalAccountStatus) {
        self.initialStatus = initialStatus
        self.refreshedStatus = refreshedStatus
        self.claimedStatus = claimedStatus
    }

    func loadStatus() -> LocalAccountStatus { initialStatus }
    func startQrLogin() async throws -> QrLoginSession { throw AccountSessionError.missingAccount }
    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload { throw AccountSessionError.missingAccount }
    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func refreshSignInStatus() async throws -> LocalAccountStatus { refreshedStatus }
    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus {
        claimDailyRewardCallCount += 1
        return claimedStatus
    }
    func loadResignInfo() async throws -> SignInResignInfoPayload { throw AccountSessionError.missingAccount }
    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus { throw AccountSessionError.missingAccount }
    func signInWebVerificationContext() throws -> SignInWebVerificationContext { throw AccountSessionError.missingAccount }
    func refreshLoginTokens() async throws -> LocalAccountStatus { refreshedStatus }
    func loadGachaRecords() async throws -> [GachaRecord] { [] }
    func signOut() throws -> LocalAccountStatus { .signedOut }
}

private final class InMemoryAutoSignInStore: AutoSignInStoring {
    var isEnabled: Bool
    private var completedDays: [String: String] = [:]
    private var failureDates: [String: Date] = [:]
    private var scheduledAttemptDates: [String: Date] = [:]

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func completedDay(accountID: String, uid: String) -> String? {
        completedDays[key(accountID: accountID, uid: uid)]
    }

    func setCompletedDay(_ day: String, accountID: String, uid: String) {
        completedDays[key(accountID: accountID, uid: uid)] = day
    }

    func lastFailureDate(accountID: String, uid: String) -> Date? {
        failureDates[key(accountID: accountID, uid: uid)]
    }

    func setLastFailureDate(_ date: Date?, accountID: String, uid: String) {
        let key = key(accountID: accountID, uid: uid)
        if let date {
            failureDates[key] = date
        } else {
            failureDates.removeValue(forKey: key)
        }
    }

    func scheduledAttemptDate(accountID: String, uid: String, serverDay: String) -> Date? {
        scheduledAttemptDates[scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay)]
    }

    func setScheduledAttemptDate(_ date: Date, accountID: String, uid: String, serverDay: String) {
        scheduledAttemptDates[scheduledAttemptKey(accountID: accountID, uid: uid, serverDay: serverDay)] = date
    }

    private func key(accountID: String, uid: String) -> String {
        "\(accountID).\(uid)"
    }

    private func scheduledAttemptKey(accountID: String, uid: String, serverDay: String) -> String {
        "\(accountID).\(uid).\(serverDay)"
    }
}

private final class InMemoryWidgetSnapshotStore: WidgetSnapshotStoring {
    var savedSnapshots: [WidgetSnapshot] = []
    var snapshot: WidgetSnapshot = .empty

    func load() throws -> WidgetSnapshot {
        snapshot
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        self.snapshot = snapshot
        savedSnapshots.append(snapshot)
    }
}

private final class InMemoryWidgetTimelineReloader: WidgetTimelineReloading {
    private(set) var reloadedKinds: [String] = []

    func reloadTimelines(ofKind kind: String) {
        reloadedKinds.append(kind)
    }
}

private struct ThrowingWidgetSnapshotStore: WidgetSnapshotStoring {
    func load() throws -> WidgetSnapshot {
        .empty
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        throw WidgetSnapshotTestError.saveFailed
    }
}

private enum WidgetSnapshotTestError: Error {
    case saveFailed
}
