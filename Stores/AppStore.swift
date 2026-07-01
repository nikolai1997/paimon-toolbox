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
    var gachaSummary = GachaSummary(totalPulls: 0, fiveStarCount: 0, fourStarCount: 0, pitySinceLastFiveStar: 0)
    var plans: [CultivationPlan] = []
    var overviewData: OverviewData = .empty
    var accountStatus: LocalAccountStatus = .signedOut
    var qrLoginSession: QrLoginSession?
    var qrLoginState: QrLoginPollingState = .idle
    var confirmedQrLoginResult: QrLoginResultPayload?
    var accountVerification: AccountVerificationState?
    var accountResignInfo: SignInResignInfoPayload?
    var isAccountBusy = false
    var searchText: String = ""
    var errorMessage: String?
    var successMessage: String?
    var metadataSourceDescription: String = "内置基础数据"
    var widgetSnapshot: WidgetSnapshot = .empty

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

    init(
        metadataService: MetadataServicing = BundledMetadataService(),
        overviewDataService: OverviewDataServicing = LocalOverviewDataService(),
        gachaService: GachaLogServicing = LocalGachaLogService(),
        plannerService: PlannerServicing = LocalPlannerService(),
        accountService: AccountSessionServicing = LocalAccountSessionService(),
        autoSignInStore: AutoSignInStoring = UserDefaultsAutoSignInStore(),
        tokenRefreshStore: AccountTokenRefreshStoring = UserDefaultsAccountTokenRefreshStore(),
        widgetSnapshotStore: WidgetSnapshotStoring? = nil,
        widgetTimelineReloader: WidgetTimelineReloading = WidgetTimelineReloader()
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
            gachaSummary = gachaService.summary(for: gachaRecords)
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
        if accountStatus.isSignedIn {
            try? await refreshLoginTokensIfNeeded(now: now)
            accountResignInfo = try? await accountService.loadResignInfo()
        } else {
            accountResignInfo = nil
        }

        if metadata != nil {
            await refreshRemoteMetadataIfNeeded(
                urlString: remoteMetadataURLString,
                offlinePackageURLString: offlinePackageURLString,
                isEnabled: autoRefreshRemoteMetadata
            )
        }

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
            gachaSummary = gachaService.summary(for: gachaRecords)
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
            gachaSummary = gachaService.summary(for: gachaRecords)
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
            try await gachaService.exportRecords(gachaRecords, to: url)
            successMessage = "已导出 UIGF 文件"
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    func syncGachaRecordsFromAccount() async {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            let remoteRecords = try await accountService.loadGachaRecords()
            let merged = GachaLogDocument.mergedRecords(existing: gachaRecords, imported: remoteRecords)
            try await gachaService.replaceRecords(merged)
            gachaRecords = merged
            gachaSummary = gachaService.summary(for: merged)
            successMessage = "已从账号更新 \(remoteRecords.count) 条祈愿记录，当前共 \(merged.count) 条"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            successMessage = nil
            errorMessage = "账号更新祈愿记录失败：\(error.localizedDescription)"
        }
    }

    func updateRequirement(planID: CultivationPlan.ID, requirementID: MaterialRequirement.ID, owned: Int) async {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let requirementIndex = plans[planIndex].requirements.firstIndex(where: { $0.id == requirementID }) else {
            return
        }
        plans[planIndex].requirements[requirementIndex].owned = max(owned, 0)
        await savePlans(message: "养成计划已保存")
    }

    func deletePlans(at offsets: IndexSet) async {
        plans.remove(atOffsets: offsets)
        await savePlans(message: "养成计划已删除")
    }

    func deletePlan(id: CultivationPlan.ID) async {
        plans.removeAll { $0.id == id }
        await savePlans(message: "养成计划已删除")
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
        plans.insert(plan, at: 0)
        await savePlans(message: "已创建 \(character.name) 的养成计划")
    }

    func createWeaponPlan(
        for weapon: Weapon,
        currentLevel: Int = 1,
        targetLevel: Int = 90
    ) async {
        let plan = CultivationPlan(
            id: UUID(),
            targetName: weapon.name,
            targetKind: "武器",
            targetIconURL: weapon.iconURL,
            currentLevel: currentLevel,
            targetLevel: targetLevel,
            requirements: materialRequirements(
                from: weapon.materials,
                suggestedRequired: [5, 23, 27]
            )
        )
        plans.insert(plan, at: 0)
        await savePlans(message: "已创建 \(weapon.name) 的养成计划")
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
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            qrLoginSession = try await accountService.startQrLogin()
            qrLoginState = .waiting
            confirmedQrLoginResult = nil
            accountVerification = nil
            accountResignInfo = nil
            successMessage = nil
            errorMessage = nil
        } catch {
            qrLoginSession = nil
            qrLoginState = .failed(error.localizedDescription)
            confirmedQrLoginResult = nil
            errorMessage = "生成登录二维码失败：\(error.localizedDescription)"
        }
    }

    func queryQrLogin(ticket: String) async {
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            let result = try await accountService.queryQrLoginResult(ticket: ticket)
            switch result.pollingState {
            case .confirmed:
                confirmedQrLoginResult = result
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
            qrLoginState = .failed(error.localizedDescription)
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func finishConfirmedQrLogin(now: Date = Date()) async {
        guard let confirmedQrLoginResult else { return }
        isAccountBusy = true
        defer { isAccountBusy = false }

        do {
            accountStatus = try await accountService.completeQrLogin(result: confirmedQrLoginResult)
            self.confirmedQrLoginResult = nil
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
            if error is CancellationError {
                qrLoginState = .confirmed
                successMessage = nil
                errorMessage = "登录已确认，正在同步账号数据，请稍候。"
                return
            }
            qrLoginState = .confirmed
            successMessage = nil
            errorMessage = "登录已确认，但同步账号数据失败：\(error.localizedDescription)"
        }
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
            accountResignInfo = try? await accountService.loadResignInfo()
            accountVerification = nil
            markDailySignInCompletedIfPossible(now: now)
            clearDailySignInFailureIfPossible(now: now)
            successMessage = "签到完成"
            errorMessage = nil
            publishWidgetSnapshot()
        } catch let error as AccountSessionError {
            markDailySignInFailure(context, now: now)
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
            accountResignInfo = try? await accountService.loadResignInfo()
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
            qrLoginSession = nil
            qrLoginState = .idle
            accountVerification = nil
            accountResignInfo = nil
            successMessage = "已退出账号"
            errorMessage = nil
            cancelAutomaticSignInWake()
            publishWidgetSnapshot(allowEmptySnapshot: true)
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
            accountVerification = nil
            markDailySignInCompletedIfPossible(now: now)
            clearDailySignInFailureIfPossible(now: now)
            successMessage = "自动签到完成"
            errorMessage = nil
        } catch let error as AccountSessionError {
            markDailySignInFailure(context, now: now)
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
                errorMessage = "自动签到需要安全验证：\(error.localizedDescription)"
            default:
                errorMessage = "自动签到失败：\(error.localizedDescription)"
            }
        } catch {
            markDailySignInFailure(context, now: now)
            successMessage = nil
            errorMessage = "自动签到失败：\(error.localizedDescription)"
        }
    }

    private func accountOperationWithTokenRefreshRetry<T>(
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

        let message = error.localizedDescription.lowercased()
        return message.contains("登录状态失效")
            || message.contains("重新登录")
            || message.contains("未登录")
            || message.contains("cookie")
            || message.contains("token")
            || message.contains("stoken")
            || message.contains("ltoken")
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
        if let scheduledDate = autoSignInStore.scheduledAttemptDate(
            accountID: context.accountID,
            uid: context.uid,
            serverDay: context.serverDay
        ) {
            return scheduledDate
        }

        let scheduledDate = Self.randomMorningSignInDate(serverDateKey: context.serverDateKey, region: context.region)
        autoSignInStore.setScheduledAttemptDate(
            scheduledDate,
            accountID: context.accountID,
            uid: context.uid,
            serverDay: context.serverDay
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

    private static func makeWidgetSnapshotStore() -> WidgetSnapshotStoring {
        do {
            return try LocalWidgetSnapshotStore()
        } catch {
            return FailingWidgetSnapshotStore(error: error)
        }
    }

    private func publishWidgetSnapshot(generatedAt: Date = Date(), allowEmptySnapshot: Bool = false) {
        var snapshot = WidgetSnapshot.make(
            accountStatus: accountStatus,
            gachaRecords: gachaRecords,
            gachaSummary: gachaSummary,
            plans: plans,
            generatedAt: generatedAt
        )
        if !allowEmptySnapshot, !snapshot.hasDisplayableContent, widgetSnapshot.hasDisplayableContent {
            snapshot = widgetSnapshot
        }
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

    private static func randomMorningSignInDate(serverDateKey: String, region: String) -> Date {
        let parts = serverDateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return Date()
        }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = AutoSignInSettings.morningWindowStartHour
        components.minute = 0
        components.second = 0

        guard let start = serverCalendar(for: region).date(from: components) else {
            return Date()
        }

        let windowSeconds = max(
            1,
            (AutoSignInSettings.morningWindowEndHour - AutoSignInSettings.morningWindowStartHour) * 60 * 60
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

    private func savePlans(message: String) async {
        do {
            try await plannerService.savePlans(plans)
            successMessage = message
            errorMessage = nil
            publishWidgetSnapshot()
        } catch {
            errorMessage = "保存养成计划失败：\(error.localizedDescription)"
        }
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
        isEnabled: Bool
    ) async {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
            return
        }

        do {
            metadata = try await metadataService.refreshMetadata(from: url)
            try await reloadOverviewData()
            metadataSourceDescription = url.absoluteString
            successMessage = "资料库已自动从 GitHub 更新"
            errorMessage = nil
        } catch {
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
