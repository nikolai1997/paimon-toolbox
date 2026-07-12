import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppStore {
    private static let widgetLogger = Logger(subsystem: "com.nikolai.paimon-toolbox", category: "WidgetSnapshot")

    var selectedSection: AppSection = .overview
    var metadata: MetadataBundle?
    var gachaRecords: [GachaRecord] = []
    var selectedGachaUID: String?
    var gachaSummary = GachaSummary(totalPulls: 0, fiveStarCount: 0, fourStarCount: 0, activityPity: 0, standardPity: 0)
    var plans: [CultivationPlan] = []
    var overviewData: OverviewData = .empty
    var accountStatus: LocalAccountStatus = .signedOut {
        didSet {
            if let uid = accountStatus.selectedRole?.uid, !uid.isEmpty {
                selectedGachaUID = uid
            } else if oldValue.isSignedIn,
                      let uid = oldValue.selectedRole?.uid,
                      !uid.isEmpty {
                selectedGachaUID = uid
            }
            if oldValue.isSignedIn != accountStatus.isSignedIn
                || oldValue.selectedRole?.uid != accountStatus.selectedRole?.uid {
                refreshGachaSummary()
            }
        }
    }
    var qrLoginSession: QrLoginSession?
    var qrLoginSessionID: UUID?
    var qrLoginState: QrLoginPollingState = .idle
    var confirmedQrLoginResult: QrLoginResultPayload?
    var confirmedQrLoginSessionID: UUID?
    var qrLoginSyncError: String?
    var accountVerification: AccountVerificationState?
    var accountResignInfo: SignInResignInfoPayload?
    var isAccountBusy = false
    var searchText: String = ""
    var errorMessage: String?
    var successMessage: String?
    var metadataSourceDescription: String = "内置基础数据"
    var widgetSnapshot: WidgetSnapshot = .empty

    var canRetryConfirmedQrLoginSync: Bool {
        confirmedQrLoginResult != nil
            && qrLoginState == .confirmed
            && qrLoginSyncError != nil
    }

    var availableGachaUIDs: [String] {
        Set(gachaRecords.compactMap(\.uid).filter { !$0.isEmpty }).sorted()
    }

    var hasUnassignedGachaRecords: Bool {
        gachaRecords.contains { $0.uid == nil || $0.uid?.isEmpty == true }
    }

    var activeGachaUID: String? {
        if accountStatus.isSignedIn,
           let uid = accountStatus.selectedRole?.uid,
           !uid.isEmpty {
            return uid
        }
        if let selectedGachaUID, availableGachaUIDs.contains(selectedGachaUID) {
            return selectedGachaUID
        }
        if selectedGachaUID == nil, hasUnassignedGachaRecords {
            return nil
        }
        return availableGachaUIDs.first
    }

    var activeGachaRecords: [GachaRecord] {
        if accountStatus.isSignedIn,
           let uid = accountStatus.selectedRole?.uid,
           !uid.isEmpty {
            return GachaRecord.sortedNewestFirst(gachaRecords.filter { $0.uid == uid })
        }

        if let activeGachaUID {
            return GachaRecord.sortedNewestFirst(gachaRecords.filter { $0.uid == activeGachaUID })
        }
        return GachaRecord.sortedNewestFirst(gachaRecords.filter { $0.uid == nil || $0.uid?.isEmpty == true })
    }

    @ObservationIgnored private var automaticSignInWakeTask: Task<Void, Never>?
    @ObservationIgnored private var automaticSignInWakeDate: Date?

    private let metadataService: MetadataServicing
    private let overviewDataService: OverviewDataServicing
    private let gachaService: GachaLogServicing
    private let plannerService: PlannerServicing
    private let accountService: AccountSessionServicing
    private let autoSignInStore: AutoSignInStoring
    private let tokenRefreshStore: AccountTokenRefreshStoring
    private let widgetSnapshotStore: WidgetSnapshotStoring
    private let widgetTimelineReloader: WidgetTimelineReloading
    private let signInRiskConfirmationDelayNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        metadataService: MetadataServicing = BundledMetadataService(),
        overviewDataService: OverviewDataServicing = LocalOverviewDataService(),
        gachaService: GachaLogServicing = LocalGachaLogService(),
        plannerService: PlannerServicing = LocalPlannerService(),
        accountService: AccountSessionServicing = LocalAccountSessionService(),
        autoSignInStore: AutoSignInStoring = UserDefaultsAutoSignInStore(),
        tokenRefreshStore: AccountTokenRefreshStoring = UserDefaultsAccountTokenRefreshStore(),
        widgetSnapshotStore: WidgetSnapshotStoring? = nil,
        widgetTimelineReloader: WidgetTimelineReloading = WidgetTimelineReloader(),
        signInRiskConfirmationDelayNanoseconds: UInt64 = AutoSignInSettings.riskStatusConfirmationDelayNanoseconds,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.metadataService = metadataService
        self.overviewDataService = overviewDataService
        self.gachaService = gachaService
        self.plannerService = plannerService
        self.accountService = accountService
        self.autoSignInStore = autoSignInStore
        self.tokenRefreshStore = tokenRefreshStore
        self.widgetSnapshotStore = widgetSnapshotStore ?? Self.makeWidgetSnapshotStore()
        self.widgetTimelineReloader = widgetTimelineReloader
        self.signInRiskConfirmationDelayNanoseconds = signInRiskConfirmationDelayNanoseconds
        self.sleep = sleep
        self.widgetSnapshot = (try? self.widgetSnapshotStore.load()) ?? .empty
    }

    func routeDeepLink(_ url: URL) {
        guard let deepLink = AppDeepLink(url: url) else { return }
        switch deepLink {
        case .accountSignIn:
            selectedSection = .account
        case .gacha:
            selectedSection = .gachaLog
        case .planner:
            selectedSection = .planner
        case .overview:
            selectedSection = .overview
        case .widgetRefresh:
            selectedSection = .overview
            Task {
                await refreshWidgetSnapshotFromWidget()
            }
        }
    }

    func selectGachaUID(_ uid: String?) {
        guard uid == nil || availableGachaUIDs.contains(uid!) else { return }
        selectedGachaUID = uid
        refreshGachaSummary()
        publishWidgetSnapshot()
    }

    func load(
        remoteMetadataURLString: String = RemoteDataSettings.githubMetadataURLString,
        offlinePackageURLString: String = RemoteDataSettings.offlinePackageURLString,
        autoRefreshRemoteMetadata: Bool = RemoteDataSettings.isAutoRefreshEnabled,
        now: Date = Date()
    ) async {
        successMessage = nil
        errorMessage = nil
        var loadErrors: [String] = []

        do {
            metadata = try await metadataService.loadMetadata()
            metadataSourceDescription = "本机缓存或内置基础数据"
        } catch {
            metadata = nil
            loadErrors.append("资料库加载失败：\(error.localizedDescription)")
        }

        do {
            overviewData = try await overviewDataService.loadOverviewData()
        } catch {
            overviewData = .empty
            loadErrors.append("公开活动数据加载失败：\(error.localizedDescription)")
        }

        do {
            gachaRecords = try await gachaService.loadRecords()
            normalizeGachaUIDSelection()
            refreshGachaSummary()
        } catch {
            gachaRecords = []
            gachaSummary = gachaService.summary(for: [])
            loadErrors.append("祈愿记录加载失败：\(error.localizedDescription)")
        }

        do {
            plans = try await plannerService.loadPlans()
        } catch {
            plans = []
            loadErrors.append("养成计划加载失败：\(error.localizedDescription)")
        }

        accountStatus = accountService.loadStatus()
        refreshGachaSummary()
        if accountStatus.isSignedIn {
            try? await refreshLoginTokensIfNeeded(now: now)
            accountResignInfo = try? await accountService.loadResignInfo()
        } else {
            accountResignInfo = nil
        }

        await refreshRemoteMetadataIfNeeded(
            urlString: remoteMetadataURLString,
            offlinePackageURLString: offlinePackageURLString,
            isEnabled: autoRefreshRemoteMetadata,
            now: now
        )

        if errorMessage == nil, !loadErrors.isEmpty {
            errorMessage = loadErrors.joined(separator: "；")
        }

        await performAutoSignInIfNeeded(now: now)
        publishWidgetSnapshot(generatedAt: now)
    }

    func refreshMetadata(from urlString: String) async {
        guard let url = URL(string: urlString), !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = MetadataRefreshError.invalidURL.localizedDescription
            return
        }

        do {
            metadata = try await metadataService.refreshMetadata(from: url)
            try await reloadOverviewData()
            metadataSourceDescription = url.absoluteString
            successMessage = "资料库已从静态资源更新"
            errorMessage = nil
        } catch {
            errorMessage = "资料库更新失败：\(error.localizedDescription)"
        }
    }

    func importMetadataPackage(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            metadata = try await metadataService.importMetadataPackage(from: url)
            try await reloadOverviewData()
            metadataSourceDescription = "离线数据包：\(url.lastPathComponent)"
            successMessage = "已导入离线资料库"
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "离线数据包导入失败：\(error.localizedDescription)"
        }
    }

    func importGachaRecords(from url: URL) async {
        do {
            gachaRecords = try await gachaService.importRecords(from: url, into: gachaRecords)
            normalizeGachaUIDSelection()
            refreshGachaSummary()
            successMessage = "已导入并合并 \(gachaRecords.count) 条祈愿记录"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func reloadLocalGachaRecords() async {
        do {
            gachaRecords = try await gachaService.loadRecords()
            normalizeGachaUIDSelection()
            refreshGachaSummary()
            successMessage = gachaRecords.isEmpty ? nil : "已读取本机 \(gachaRecords.count) 条祈愿记录"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            gachaRecords = []
            gachaSummary = gachaService.summary(for: [])
            successMessage = nil
            errorMessage = "本地祈愿记录读取失败：\(error.localizedDescription)"
        }
    }

    func exportGachaRecords(to url: URL) async {
        do {
            try await gachaService.exportRecords(activeGachaRecords, to: url)
            successMessage = "已导出当前账号 UIGF 文件"
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func syncGachaRecordsFromAccount() async {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            let loadedRecords = try await accountService.loadGachaRecords()
            let selectedUID = accountStatus.selectedRole?.uid
            let remoteRecords = loadedRecords.map { record in
                var ownedRecord = record
                ownedRecord.uid = selectedUID ?? ownedRecord.uid
                return ownedRecord
            }
            let merged = GachaLogDocument.mergedRecords(existing: gachaRecords, imported: remoteRecords)
            try await gachaService.replaceRecords(merged)
            gachaRecords = merged
            normalizeGachaUIDSelection()
            refreshGachaSummary()
            successMessage = "已从账号更新 \(remoteRecords.count) 条祈愿记录，当前共 \(merged.count) 条"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            successMessage = nil
            errorMessage = "账号更新祈愿记录失败：\(error.localizedDescription)"
        }
    }

    func updateRequirement(planID: CultivationPlan.ID, requirementID: MaterialRequirement.ID, owned: Int) async {
        var candidate = plans
        guard let planIndex = candidate.firstIndex(where: { $0.id == planID }),
              let requirementIndex = candidate[planIndex].requirements.firstIndex(where: { $0.id == requirementID }) else {
            return
        }
        candidate[planIndex].requirements[requirementIndex].owned = max(owned, 0)
        await commitPlans(candidate, message: "养成计划已保存")
    }

    func deletePlans(at offsets: IndexSet) async {
        var candidate = plans
        candidate.remove(atOffsets: offsets)
        await commitPlans(candidate, message: "养成计划已删除")
    }

    func deletePlan(id: CultivationPlan.ID) async {
        let candidate = plans.filter { $0.id != id }
        await commitPlans(candidate, message: "养成计划已删除")
    }

    func createCharacterPlan(
        for character: GameCharacter,
        currentLevel: Int = 1,
        targetLevel: Int = 90,
        normalAttackCurrentLevel: Int = 1,
        normalAttackTargetLevel: Int = 1,
        elementalSkillCurrentLevel: Int = 1,
        elementalSkillTargetLevel: Int = 1,
        elementalBurstCurrentLevel: Int = 1,
        elementalBurstTargetLevel: Int = 1
    ) async {
        let plan = CultivationPlan(
            id: UUID(),
            targetName: character.name,
            targetKind: "角色",
            targetIconURL: character.iconURL ?? character.portraitURL,
            currentLevel: currentLevel,
            targetLevel: targetLevel,
            normalAttackCurrentLevel: normalAttackCurrentLevel,
            normalAttackTargetLevel: normalAttackTargetLevel,
            elementalSkillCurrentLevel: elementalSkillCurrentLevel,
            elementalSkillTargetLevel: elementalSkillTargetLevel,
            elementalBurstCurrentLevel: elementalBurstCurrentLevel,
            elementalBurstTargetLevel: elementalBurstTargetLevel,
            requirements: characterRequirements(
                for: character,
                currentLevel: currentLevel,
                targetLevel: targetLevel,
                normalAttackCurrentLevel: normalAttackCurrentLevel,
                normalAttackTargetLevel: normalAttackTargetLevel,
                elementalSkillCurrentLevel: elementalSkillCurrentLevel,
                elementalSkillTargetLevel: elementalSkillTargetLevel,
                elementalBurstCurrentLevel: elementalBurstCurrentLevel,
                elementalBurstTargetLevel: elementalBurstTargetLevel
            )
        )
        await commitPlans([plan] + plans, message: "已创建 \(character.name) 的养成计划")
    }

    func createWeaponPlan(
        for weapon: Weapon,
        currentLevel: Int = 1,
        targetLevel: Int = 90
    ) async {
        let result = CultivationCalculator.weaponRequirements(
            stages: weapon.ascensionStages,
            levelRange: CultivationLevelRange(current: currentLevel, target: targetLevel)
        )
        guard case .exact(let totals) = result else {
            successMessage = nil
            errorMessage = "当前资料缺少完整武器突破数量，暂时无法创建精确计划"
            return
        }
        let plan = CultivationPlan(
            id: UUID(),
            targetName: weapon.name,
            targetKind: "武器",
            targetIconURL: weapon.iconURL,
            currentLevel: currentLevel,
            targetLevel: targetLevel,
            requirements: CultivationCalculator.materialRequirements(from: totals)
        )
        await commitPlans([plan] + plans, message: "已创建 \(weapon.name) 的养成计划")
    }

    private func characterRequirements(
        for character: GameCharacter,
        currentLevel: Int,
        targetLevel: Int,
        normalAttackCurrentLevel: Int,
        normalAttackTargetLevel: Int,
        elementalSkillCurrentLevel: Int,
        elementalSkillTargetLevel: Int,
        elementalBurstCurrentLevel: Int,
        elementalBurstTargetLevel: Int
    ) -> [MaterialRequirement] {
        if let cultivation = character.cultivation, cultivation.hasExactMaterialTiers {
            let totals = CultivationCalculator.characterRequirements(
                materials: cultivation,
                levelRange: CultivationLevelRange(current: currentLevel, target: targetLevel),
                normalAttackRange: CultivationLevelRange(current: normalAttackCurrentLevel, target: normalAttackTargetLevel),
                elementalSkillRange: CultivationLevelRange(current: elementalSkillCurrentLevel, target: elementalSkillTargetLevel),
                elementalBurstRange: CultivationLevelRange(current: elementalBurstCurrentLevel, target: elementalBurstTargetLevel)
            )
            return CultivationCalculator.materialRequirements(from: totals)
        }

        return materialRequirements(
            from: character.materials,
            suggestedRequired: [6, 46, 168, 129, 114, 18]
        )
    }

    func startQrLogin() async {
        let sessionID = UUID()
        qrLoginSession = nil
        qrLoginSessionID = sessionID
        confirmedQrLoginResult = nil
        confirmedQrLoginSessionID = nil
        qrLoginSyncError = nil
        qrLoginState = .idle
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            let session = try await accountService.startQrLogin()
            guard qrLoginSessionID == sessionID else { return }
            qrLoginSession = session
            qrLoginState = .waiting
            confirmedQrLoginResult = nil
            qrLoginSyncError = nil
            accountVerification = nil
            accountResignInfo = nil
            successMessage = nil
            errorMessage = nil
        } catch {
            guard qrLoginSessionID == sessionID else { return }
            qrLoginSession = nil
            qrLoginSessionID = nil
            qrLoginState = .failed(error.localizedDescription)
            confirmedQrLoginResult = nil
            confirmedQrLoginSessionID = nil
            qrLoginSyncError = nil
            errorMessage = "生成登录二维码失败：\(error.localizedDescription)"
        }
    }

    func queryQrLogin(ticket: String, sessionID: UUID) async {
        guard isActiveQrLogin(ticket: ticket, sessionID: sessionID) else { return }
        isAccountBusy = true
        defer {
            if qrLoginSessionID == sessionID || qrLoginSessionID == nil {
                isAccountBusy = false
            }
        }

        do {
            let result = try await accountService.queryQrLoginResult(ticket: ticket)
            guard isActiveQrLogin(ticket: ticket, sessionID: sessionID) else { return }
            switch result.pollingState {
            case .confirmed:
                confirmedQrLoginResult = result
                confirmedQrLoginSessionID = sessionID
                qrLoginSyncError = nil
                qrLoginSession = nil
                qrLoginState = .confirmed
                accountVerification = nil
                successMessage = "登录已确认，正在同步账号数据"
                errorMessage = nil
            case .waiting, .scanned:
                qrLoginState = result.pollingState
                successMessage = nil
                errorMessage = nil
            case .expired:
                qrLoginState = .expired
                successMessage = nil
                errorMessage = "二维码已过期，请刷新后重试。"
            case .canceled:
                qrLoginState = .canceled
                successMessage = nil
                errorMessage = "登录已取消，请重新扫码。"
            case .idle, .failed:
                qrLoginState = result.pollingState
                successMessage = nil
                errorMessage = "登录失败：\(result.pollingState.localizedDescription)"
            }
        } catch let error as AccountSessionError {
            guard isActiveQrLogin(ticket: ticket, sessionID: sessionID) else { return }
            switch error {
            case .qrLoginPending(let state):
                qrLoginState = state
                successMessage = nil
                switch state {
                case .waiting, .scanned:
                    errorMessage = nil
                case .expired:
                    errorMessage = "二维码已过期，请刷新后重试。"
                case .canceled:
                    errorMessage = "登录已取消，请重新扫码。"
                case .failed:
                    errorMessage = "登录失败：\(error.localizedDescription)"
                case .idle, .confirmed:
                    errorMessage = error.localizedDescription
                }
            default:
                qrLoginState = .failed(error.localizedDescription)
                errorMessage = "登录失败：\(error.localizedDescription)"
            }
        } catch {
            guard isActiveQrLogin(ticket: ticket, sessionID: sessionID) else { return }
            qrLoginState = .failed(error.localizedDescription)
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func cancelQrLogin(sessionID: UUID? = nil) {
        if let sessionID, qrLoginSessionID != sessionID {
            return
        }
        qrLoginSession = nil
        qrLoginSessionID = nil
        confirmedQrLoginResult = nil
        confirmedQrLoginSessionID = nil
        qrLoginSyncError = nil
        qrLoginState = .canceled
        isAccountBusy = false
    }

    func finishConfirmedQrLogin(sessionID: UUID, now: Date = Date()) async {
        guard isActiveConfirmedQrLogin(sessionID: sessionID),
              let confirmedQrLoginResult else { return }
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            let completedStatus = try await accountService.completeQrLogin(result: confirmedQrLoginResult)
            guard isActiveConfirmedQrLogin(sessionID: sessionID) else { return }
            accountStatus = completedStatus
            refreshGachaSummary()
            self.confirmedQrLoginResult = nil
            confirmedQrLoginSessionID = nil
            qrLoginSessionID = nil
            qrLoginSyncError = nil
            qrLoginSession = nil
            qrLoginState = .confirmed
            accountVerification = nil
            markLoginTokensRefreshed(at: now)
            accountResignInfo = try? await accountService.loadResignInfo()
            successMessage = "米哈游账号已登录"
            errorMessage = nil
            isAccountBusy = false
            await performAutoSignInIfNeeded(now: now)
            publishWidgetSnapshot()
        } catch {
            guard isActiveConfirmedQrLogin(sessionID: sessionID) else { return }
            if error is CancellationError {
                qrLoginState = .confirmed
                qrLoginSyncError = "登录已确认，正在同步账号数据，请稍候。"
                successMessage = nil
                errorMessage = qrLoginSyncError
                return
            }
            qrLoginState = .confirmed
            qrLoginSyncError = "登录已确认，但同步账号数据失败：\(error.localizedDescription)"
            successMessage = nil
            errorMessage = qrLoginSyncError
        }
    }

    func retryConfirmedQrLoginSync(now: Date = Date()) async {
        guard canRetryConfirmedQrLoginSync,
              let sessionID = confirmedQrLoginSessionID else { return }
        successMessage = "正在重新同步账号数据"
        qrLoginSyncError = nil
        errorMessage = nil
        await finishConfirmedQrLogin(sessionID: sessionID, now: now)
    }

    func refreshSignInStatus(now: Date = Date()) async {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.refreshSignInStatus()
            }
            accountResignInfo = try? await accountService.loadResignInfo()
            accountVerification = nil
            successMessage = "签到状态已刷新"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            errorMessage = "刷新签到状态失败：\(error.localizedDescription)"
        }
    }

    func refreshWidgetSnapshotFromWidget(now: Date = Date()) async {
        let storedStatus = accountService.loadStatus()
        if storedStatus.isSignedIn {
            accountStatus = storedStatus
        }

        if accountStatus.isSignedIn {
            await refreshSignInStatus(now: now)
        } else {
            successMessage = "小组件状态已刷新"
            errorMessage = nil
            publishWidgetSnapshot(generatedAt: now)
        }
    }

    func claimDailyReward(now: Date = Date()) async {
        await claimDailyReward(verification: nil, now: now)
    }

    func completeSignInVerification(_ verification: SignInVerificationResult) async {
        await claimDailyReward(verification: verification, now: Date())
    }

    func completeResignVerification(_ verification: SignInVerificationResult) async {
        await claimResignReward(verification: verification, now: Date())
    }

    private func claimDailyReward(verification: SignInVerificationResult?, now: Date) async {
        guard verification != nil else {
            await claimDailyRewardIfNeeded(now: now)
            return
        }

        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.claimDailyReward(verification: verification)
            }
            try requireConfirmedDailySignIn()
            accountResignInfo = try? await accountService.loadResignInfo()
            accountVerification = nil
            markDailySignInCompletedIfPossible(now: now)
            clearDailySignInFailureIfPossible(now: now)
            successMessage = "签到完成"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch let error as AccountSessionError {
            markDailySignInFailureIfPossible(now: now)
            successMessage = nil
            switch error {
            case .requiresVerification(let payload):
                accountVerification = AccountVerificationState(
                    message: error.localizedDescription,
                    url: HoYoConstants.signInVerificationURL,
                    payload: payload,
                    webContext: try? accountService.signInWebVerificationContext(),
                    purpose: .dailySignIn
                )
                errorMessage = error.localizedDescription
            default:
                errorMessage = "签到失败：\(error.localizedDescription)"
            }
        } catch {
            successMessage = nil
            errorMessage = "签到失败：\(error.localizedDescription)"
        }
    }

    private func claimDailyRewardIfNeeded(now: Date) async {
        guard let context = dailySignInContext(now: now) else {
            errorMessage = "签到失败：未登录米游社账号或未绑定原神角色。"
            successMessage = nil
            return
        }

        if isDailySignInCompleted(context) {
            successMessage = "今日已签到"
            errorMessage = nil
            return
        }

        if isDailySignInInFailureCooldown(context, now: now) {
            successMessage = nil
            errorMessage = "签到刚刚失败过，请稍后再试，避免频繁请求触发风控。"
            return
        }

        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            try await refreshLoginTokensIfNeeded(now: now)
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.refreshSignInStatus()
            }
            accountResignInfo = try? await accountService.loadResignInfo()

            if accountStatus.signInSummary?.isTodaySigned == true {
                markDailySignInCompleted(context)
                clearDailySignInFailure(context)
                accountVerification = nil
                successMessage = "今日已签到"
                errorMessage = nil
                publishWidgetSnapshot()
                return
            }

            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.claimDailyReward(verification: nil)
            }
            try requireConfirmedDailySignIn()
            accountResignInfo = try? await accountService.loadResignInfo()
            accountVerification = nil
            markDailySignInCompletedIfPossible(now: now)
            clearDailySignInFailureIfPossible(now: now)
            successMessage = "签到完成"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch let error as AccountSessionError {
            successMessage = nil
            switch error {
            case .requiresVerification(let payload):
                if await markDailySignInCompletedIfStatusRefreshShowsSigned(context, now: now, successMessage: "签到完成") {
                    publishWidgetSnapshot()
                    return
                }
                markDailySignInFailure(context, now: now)
                accountVerification = AccountVerificationState(
                    message: error.localizedDescription,
                    url: HoYoConstants.signInVerificationURL,
                    payload: payload,
                    webContext: try? accountService.signInWebVerificationContext(),
                    purpose: .dailySignIn
                )
                errorMessage = error.localizedDescription
            default:
                markDailySignInFailure(context, now: now)
                errorMessage = "签到失败：\(error.localizedDescription)"
            }
        } catch {
            markDailySignInFailure(context, now: now)
            successMessage = nil
            errorMessage = "签到失败：\(error.localizedDescription)"
        }
    }

    func claimResignReward(now: Date = Date()) async {
        await claimResignReward(verification: nil, now: now)
    }

    private func claimResignReward(verification: SignInVerificationResult?, now: Date) async {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.claimResignReward(verification: verification)
            }
            accountResignInfo = try await accountService.loadResignInfo()
            guard accountResignInfo?.signed == true else {
                throw AccountSessionError.invalidResponse("补签状态未确认成功")
            }
            accountVerification = nil
            successMessage = "补签完成"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch let error as AccountSessionError {
            successMessage = nil
            switch error {
            case .requiresVerification(let payload):
                accountVerification = AccountVerificationState(
                    message: error.localizedDescription,
                    url: HoYoConstants.signInVerificationURL,
                    payload: payload,
                    webContext: try? accountService.signInWebVerificationContext(),
                    purpose: .resign
                )
                errorMessage = error.localizedDescription
            default:
                errorMessage = "补签失败：\(error.localizedDescription)"
            }
        } catch {
            successMessage = nil
            errorMessage = "补签失败：\(error.localizedDescription)"
        }
    }

    func signOutAccount() {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            accountStatus = try accountService.signOut()
            qrLoginSyncError = nil
            qrLoginSession = nil
            qrLoginSessionID = nil
            confirmedQrLoginSessionID = nil
            qrLoginState = .idle
            accountVerification = nil
            accountResignInfo = nil
            successMessage = "已退出账号"
            errorMessage = nil
            cancelAutomaticSignInWake()
            refreshGachaSummary()
            publishWidgetSnapshot()
        } catch {
            accountStatus = accountService.loadStatus()
            successMessage = nil
            errorMessage = "退出账号失败：\(error.localizedDescription)"
        }
    }

    func runAutomaticSignInCheck(now: Date = Date()) async {
        await performAutoSignInIfNeeded(now: now)
        publishWidgetSnapshot(generatedAt: now)
    }

    func startAutomaticSignInMonitor() async {
        while !Task.isCancelled {
            await runAutomaticSignInCheck(now: Date())
            let nextWakeDate = nextAutomaticSignInMonitorDate(after: Date())
            try? await Task.sleep(nanoseconds: Self.sleepNanoseconds(until: nextWakeDate))
        }
    }

    private func performAutoSignInIfNeeded(now: Date) async {
        guard autoSignInStore.isEnabled,
              accountStatus.isSignedIn,
              !isAccountBusy,
              accountVerification == nil,
              let context = dailySignInContext(now: now) else {
            return
        }

        guard !isDailySignInCompleted(context),
              !isDailySignInInFailureCooldown(context, now: now) else {
            return
        }

        let scheduledDate = scheduledDailySignInDate(for: context)
        guard now >= scheduledDate else {
            scheduleAutomaticSignInWake(at: scheduledDate)
            return
        }

        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            try await refreshLoginTokensIfNeeded(now: now)
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.refreshSignInStatus()
            }
            guard accountStatus.signInSummary?.isTodaySigned != true else {
                markDailySignInCompleted(context)
                clearDailySignInFailure(context)
                return
            }
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.claimDailyReward(verification: nil)
            }
            try requireConfirmedDailySignIn()
            accountVerification = nil
            markDailySignInCompletedIfPossible(now: now)
            clearDailySignInFailureIfPossible(now: now)
            successMessage = "自动签到完成"
            errorMessage = nil
        } catch let error as AccountSessionError {
            successMessage = nil
            switch error {
            case .requiresVerification(let payload):
                if await markDailySignInCompletedIfStatusRefreshShowsSigned(context, now: now, successMessage: "自动签到完成") {
                    return
                }
                markDailySignInFailure(context, now: now)
                accountVerification = AccountVerificationState(
                    message: error.localizedDescription,
                    url: HoYoConstants.signInVerificationURL,
                    payload: payload,
                    webContext: try? accountService.signInWebVerificationContext(),
                    purpose: .dailySignIn
                )
                errorMessage = "自动签到需要安全验证：\(error.localizedDescription)"
            default:
                markDailySignInFailure(context, now: now)
                errorMessage = "自动签到失败：\(error.localizedDescription)"
            }
        } catch {
            markDailySignInFailure(context, now: now)
            successMessage = nil
            errorMessage = "自动签到失败：\(error.localizedDescription)"
        }
    }

    private func accountOperationWithTokenRefreshRetry<T: Sendable>(
        now: Date,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard shouldRefreshLoginTokens(after: error) else {
                throw error
            }
            try await refreshLoginTokensIfNeeded(now: now, force: true)
            return try await operation()
        }
    }

    private func refreshLoginTokensIfNeeded(now: Date, force: Bool = false) async throws {
        guard accountStatus.isSignedIn, let accountID = accountStatus.accountID else {
            return
        }
        if !force,
           let lastRefresh = tokenRefreshStore.lastRefreshDate(accountID: accountID),
           now.timeIntervalSince(lastRefresh) < AccountTokenRefreshSettings.minimumRefreshInterval {
            return
        }

        accountStatus = try await accountService.refreshLoginTokens()
        tokenRefreshStore.setLastRefreshDate(now, accountID: accountID)
    }

    private func markLoginTokensRefreshed(at date: Date) {
        guard let accountID = accountStatus.accountID else {
            return
        }
        tokenRefreshStore.setLastRefreshDate(date, accountID: accountID)
    }

    private func shouldRefreshLoginTokens(after error: Error) -> Bool {
        if case AccountSessionError.requiresVerification = error {
            return false
        }

        if let accountError = error as? AccountSessionError,
           accountError.indicatesExpiredSession {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("登录状态失效")
            || message.contains("重新登录")
            || message.contains("未登录")
            || message.contains("cookie")
            || message.contains("token")
            || message.contains("stoken")
            || message.contains("ltoken")
    }

    private func requireConfirmedDailySignIn() throws {
        guard accountStatus.signInSummary?.isTodaySigned == true else {
            throw AccountSessionError.invalidResponse("签到状态未确认成功")
        }
    }

    private func isActiveQrLogin(ticket: String, sessionID: UUID) -> Bool {
        qrLoginSessionID == sessionID && qrLoginSession?.ticket == ticket
    }

    private func isActiveConfirmedQrLogin(sessionID: UUID) -> Bool {
        qrLoginSessionID == sessionID
            && confirmedQrLoginSessionID == sessionID
            && confirmedQrLoginResult != nil
    }

    private struct DailySignInContext {
        var accountID: String
        var uid: String
        var region: String
        var serverDateKey: String
        var serverDay: String
    }

    private func dailySignInContext(now: Date) -> DailySignInContext? {
        guard accountStatus.isSignedIn,
              let accountID = accountStatus.accountID,
              let uid = accountStatus.selectedRole?.uid ?? accountStatus.signInSummary?.uid else {
            return nil
        }

        let region = accountStatus.selectedRole?.region ?? "cn_gf01"
        let serverDateKey = Self.signInServerDateKey(for: now, region: region)
        return DailySignInContext(
            accountID: accountID,
            uid: uid,
            region: region,
            serverDateKey: serverDateKey,
            serverDay: "\(region):\(serverDateKey)"
        )
    }

    private func isDailySignInCompleted(_ context: DailySignInContext) -> Bool {
        autoSignInStore.completedDay(accountID: context.accountID, uid: context.uid) == context.serverDay
    }

    private func markDailySignInCompleted(_ context: DailySignInContext) {
        autoSignInStore.setCompletedDay(context.serverDay, accountID: context.accountID, uid: context.uid)
    }

    private func markDailySignInCompletedIfPossible(now: Date) {
        guard let context = dailySignInContext(now: now) else { return }
        markDailySignInCompleted(context)
    }

    private func isDailySignInInFailureCooldown(_ context: DailySignInContext, now: Date) -> Bool {
        guard let lastFailure = autoSignInStore.lastFailureDate(accountID: context.accountID, uid: context.uid) else {
            return false
        }
        return now.timeIntervalSince(lastFailure) < AutoSignInSettings.failureCooldown
    }

    private func scheduledDailySignInDate(for context: DailySignInContext) -> Date {
        let window = AutoSignInSettings.selectedWindow
        let scheduleIdentifier = AutoSignInSettings.scheduledAttemptIdentifier(
            serverDay: context.serverDay,
            window: window
        )
        if let scheduledDate = autoSignInStore.scheduledAttemptDate(
            accountID: context.accountID,
            uid: context.uid,
            serverDay: scheduleIdentifier
        ) {
            return scheduledDate
        }

        let scheduledDate = Self.randomSignInDate(
            serverDateKey: context.serverDateKey,
            region: context.region,
            window: window
        )
        autoSignInStore.setScheduledAttemptDate(
            scheduledDate,
            accountID: context.accountID,
            uid: context.uid,
            serverDay: scheduleIdentifier
        )
        return scheduledDate
    }

    private func nextAutomaticSignInMonitorDate(after now: Date) -> Date {
        guard autoSignInStore.isEnabled,
              accountStatus.isSignedIn,
              !isAccountBusy,
              accountVerification == nil,
              let context = dailySignInContext(now: now) else {
            return now.addingTimeInterval(AutoSignInSettings.idleWakeInterval)
        }

        if isDailySignInCompleted(context) {
            let nextServerDateKey = Self.nextSignInServerDateKey(after: context.serverDateKey, region: context.region)
            let nextContext = DailySignInContext(
                accountID: context.accountID,
                uid: context.uid,
                region: context.region,
                serverDateKey: nextServerDateKey,
                serverDay: "\(context.region):\(nextServerDateKey)"
            )
            return scheduledDailySignInDate(for: nextContext)
        }

        if let lastFailure = autoSignInStore.lastFailureDate(accountID: context.accountID, uid: context.uid),
           now.timeIntervalSince(lastFailure) < AutoSignInSettings.failureCooldown {
            return lastFailure.addingTimeInterval(AutoSignInSettings.failureCooldown)
        }

        let scheduledDate = scheduledDailySignInDate(for: context)
        if now < scheduledDate {
            return scheduledDate
        }

        return now.addingTimeInterval(AutoSignInSettings.deferredWakeInterval)
    }

    private func scheduleAutomaticSignInWake(at date: Date) {
        if let automaticSignInWakeDate,
           abs(automaticSignInWakeDate.timeIntervalSince(date)) < 1 {
            return
        }

        automaticSignInWakeTask?.cancel()
        automaticSignInWakeDate = date
        let delay = Self.sleepNanoseconds(until: date)
        automaticSignInWakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.runScheduledAutomaticSignInWake(expectedDate: date)
        }
    }

    private func runScheduledAutomaticSignInWake(expectedDate: Date) async {
        if let wakeDate = automaticSignInWakeDate,
           abs(wakeDate.timeIntervalSince(expectedDate)) < 1 {
            automaticSignInWakeDate = nil
            automaticSignInWakeTask = nil
        }
        await runAutomaticSignInCheck(now: Date())
    }

    private func cancelAutomaticSignInWake() {
        automaticSignInWakeTask?.cancel()
        automaticSignInWakeTask = nil
        automaticSignInWakeDate = nil
    }

    private func markDailySignInFailure(_ context: DailySignInContext, now: Date) {
        autoSignInStore.setLastFailureDate(now, accountID: context.accountID, uid: context.uid)
    }

    private func markDailySignInFailureIfPossible(now: Date) {
        guard let context = dailySignInContext(now: now) else { return }
        markDailySignInFailure(context, now: now)
    }

    private func clearDailySignInFailure(_ context: DailySignInContext) {
        autoSignInStore.setLastFailureDate(nil, accountID: context.accountID, uid: context.uid)
    }

    private func clearDailySignInFailureIfPossible(now: Date = Date()) {
        guard let context = dailySignInContext(now: now) else { return }
        clearDailySignInFailure(context)
    }

    private func markDailySignInCompletedIfStatusRefreshShowsSigned(
        _ context: DailySignInContext,
        now: Date,
        successMessage: String
    ) async -> Bool {
        let attempts = max(1, AutoSignInSettings.riskStatusConfirmationAttempts)
        for attempt in 0..<attempts {
            if attempt > 0, signInRiskConfirmationDelayNanoseconds > 0 {
                await sleep(signInRiskConfirmationDelayNanoseconds)
            }

            if await refreshStatusShowsDailySignInCompleted(now: now) {
                accountVerification = nil
                markDailySignInCompleted(context)
                clearDailySignInFailure(context)
                self.successMessage = successMessage
                errorMessage = nil
                return true
            }
        }

        return false
    }

    private func refreshStatusShowsDailySignInCompleted(now: Date) async -> Bool {
        do {
            accountStatus = try await accountOperationWithTokenRefreshRetry(now: now) {
                try await accountService.refreshSignInStatus()
            }
        } catch {
            return false
        }

        guard accountStatus.signInSummary?.isTodaySigned == true else {
            return false
        }

        accountResignInfo = try? await accountService.loadResignInfo()
        return true
    }

    private static func makeWidgetSnapshotStore() -> WidgetSnapshotStoring {
        do {
            return try LocalWidgetSnapshotStore()
        } catch {
            return FailingWidgetSnapshotStore(error: error)
        }
    }

    private func publishWidgetSnapshot(generatedAt: Date = Date()) {
        let snapshot = WidgetSnapshot.make(
            accountStatus: accountStatus,
            gachaRecords: activeGachaRecords,
            gachaSummary: gachaSummary,
            plans: plans,
            generatedAt: generatedAt
        )
        widgetSnapshot = snapshot

        do {
            try widgetSnapshotStore.save(snapshot)
            widgetTimelineReloader.reloadTimelines(ofKind: PaimonToolboxWidgetConfiguration.kind)
        } catch {
            Self.widgetLogger.error("Failed to save widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func autoSignInDateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func signInServerDateKey(for date: Date, region: String) -> String {
        autoSignInDateKey(for: date, calendar: serverCalendar(for: region))
    }

    private static func signInServerDayKey(for date: Date, region: String) -> String {
        "\(region):\(signInServerDateKey(for: date, region: region))"
    }

    private static func nextSignInServerDateKey(after serverDateKey: String, region: String) -> String {
        let parts = serverDateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return signInServerDateKey(for: Date().addingTimeInterval(24 * 60 * 60), region: region)
        }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]

        let calendar = serverCalendar(for: region)
        guard let date = calendar.date(from: components),
              let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
            return signInServerDateKey(for: Date().addingTimeInterval(24 * 60 * 60), region: region)
        }

        return autoSignInDateKey(for: nextDate, calendar: calendar)
    }

    private static func randomSignInDate(
        serverDateKey: String,
        region: String,
        window: AutoSignInWindow
    ) -> Date {
        let parts = serverDateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return Date()
        }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = window.startHour
        components.minute = 0
        components.second = 0

        guard let start = serverCalendar(for: region).date(from: components) else {
            return Date()
        }

        let windowSeconds = max(
            1,
            (window.endHour - window.startHour) * 60 * 60
        )
        return start.addingTimeInterval(TimeInterval(Int.random(in: 0..<windowSeconds)))
    }

    private static func serverCalendar(for region: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: serverTimeZoneOffsetSeconds(for: region)) ?? .current
        return calendar
    }

    private static func serverTimeZoneOffsetSeconds(for region: String) -> Int {
        switch region {
        case "os_usa":
            return -5 * 60 * 60
        case "os_euro":
            return 1 * 60 * 60
        default:
            return 8 * 60 * 60
        }
    }

    private static func sleepNanoseconds(until date: Date, now: Date = Date()) -> UInt64 {
        let seconds = max(AutoSignInSettings.minimumWakeInterval, date.timeIntervalSince(now))
        return UInt64(seconds * 1_000_000_000)
    }

    private func commitPlans(_ candidate: [CultivationPlan], message: String) async {
        do {
            try await plannerService.savePlans(candidate)
            plans = candidate
            successMessage = message
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            errorMessage = "保存养成计划失败：\(error.localizedDescription)"
        }
    }

    private func refreshGachaSummary() {
        gachaSummary = gachaService.summary(for: activeGachaRecords)
    }

    private func normalizeGachaUIDSelection() {
        if accountStatus.isSignedIn,
           let uid = accountStatus.selectedRole?.uid,
           !uid.isEmpty {
            selectedGachaUID = uid
            return
        }
        if let selectedGachaUID, availableGachaUIDs.contains(selectedGachaUID) {
            return
        }
        if selectedGachaUID == nil, hasUnassignedGachaRecords {
            return
        }
        selectedGachaUID = availableGachaUIDs.first
    }

    private func materialRequirements(from materialNames: [String], suggestedRequired: [Int]) -> [MaterialRequirement] {
        materialNames.enumerated().map { index, name in
            let required = suggestedRequired.indices.contains(index) ? suggestedRequired[index] : 1
            return MaterialRequirement(
                id: "\(name)-\(index)",
                materialName: name,
                required: required,
                owned: 0
            )
        }
    }

    private func refreshRemoteMetadataIfNeeded(
        urlString: String,
        offlinePackageURLString: String,
        isEnabled: Bool,
        now: Date
    ) async {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
            return
        }
        guard RemoteDataSettings.shouldAttemptAutoRefresh(now: now) else {
            return
        }

        do {
            metadata = try await metadataService.refreshMetadata(from: url)
            try await reloadOverviewData()
            RemoteDataSettings.markAutoRefreshSucceeded(at: now)
            metadataSourceDescription = url.absoluteString
            successMessage = "资料库已自动从 GitHub 更新"
            errorMessage = nil
        } catch {
            RemoteDataSettings.markAutoRefreshFailed(at: now)
            successMessage = nil
            let offlineHint = offlinePackageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if offlineHint.isEmpty {
                errorMessage = "GitHub 数据更新失败：\(error.localizedDescription)。可在设置中导入网盘下载的 data-pack.zip。"
            } else {
                errorMessage = "GitHub 数据更新失败：\(error.localizedDescription)。可从网盘下载 data-pack.zip 后导入：\(offlineHint)"
            }
        }
    }

    private func reloadOverviewData() async throws {
        overviewData = try await overviewDataService.loadOverviewData()
    }
}

private struct FailingWidgetSnapshotStore: WidgetSnapshotStoring {
    var error: Error

    func load() throws -> WidgetSnapshot {
        throw error
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        throw error
    }
}
