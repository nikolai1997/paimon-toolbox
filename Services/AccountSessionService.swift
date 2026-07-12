import Foundation

@MainActor
protocol AccountSessionServicing {
    func loadStatus() -> LocalAccountStatus
    func startQrLogin() async throws -> QrLoginSession
    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload
    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus
    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus
    func refreshSignInStatus() async throws -> LocalAccountStatus
    func claimDailyReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus
    func loadResignInfo() async throws -> SignInResignInfoPayload
    func claimResignReward(verification: SignInVerificationResult?) async throws -> LocalAccountStatus
    func signInWebVerificationContext() throws -> SignInWebVerificationContext
    func refreshLoginTokens() async throws -> LocalAccountStatus
    func loadGachaRecords() async throws -> [GachaRecord]
    func signOut() throws -> LocalAccountStatus
}

struct LocalAccountSessionService: AccountSessionServicing {
    private let metadataStore: AccountMetadataStoring
    private let secretStore: AccountSecretStoring
    private let passportClient: MiHoYoPassportClient
    private let userClient: MiHoYoUserProfileLoading
    private let bindingClient: MiHoYoBindingClient
    private let signInClient: GenshinSignInClient
    private let gachaLogClient: GachaLogRemoteClient

    init(
        metadataStore: AccountMetadataStoring? = nil,
        secretStore: AccountSecretStoring? = nil,
        passportClient: MiHoYoPassportClient = MiHoYoPassportClient(),
        userClient: MiHoYoUserProfileLoading = MiHoYoUserClient(),
        bindingClient: MiHoYoBindingClient = MiHoYoBindingClient(),
        signInClient: GenshinSignInClient = GenshinSignInClient(),
        gachaLogClient: GachaLogRemoteClient = GachaLogRemoteClient()
    ) {
        self.metadataStore = metadataStore ?? Self.makeDefaultMetadataStore()
        self.secretStore = secretStore ?? Self.makeDefaultSecretStore()
        self.passportClient = passportClient
        self.userClient = userClient
        self.bindingClient = bindingClient
        self.signInClient = signInClient
        self.gachaLogClient = gachaLogClient
    }

    func loadStatus() -> LocalAccountStatus {
        guard let metadata = try? metadataStore.load() else {
            return .signedOut
        }

        do {
            guard try secretStore.load(accountID: metadata.account.accountID) != nil else {
                try? metadataStore.clear()
                return .signedOut
            }
        } catch {
            return .signedOut
        }

        return Self.status(from: metadata)
    }

    func startQrLogin() async throws -> QrLoginSession {
        try await passportClient.createQrLogin()
    }

    func queryQrLoginResult(ticket: String) async throws -> QrLoginResultPayload {
        try await passportClient.queryQrLoginStatus(ticket: ticket)
    }

    func completeQrLogin(result: QrLoginResultPayload) async throws -> LocalAccountStatus {
        var secrets = try result.accountSecrets()
        secrets = try await runAccountSyncStep("获取 LToken") {
            try await passportClient.refreshLToken(secrets: secrets)
        }
        secrets = try await runAccountSyncStep("获取 CookieToken") {
            try await passportClient.refreshCookieToken(secrets: secrets)
        }

        let roles = try await runAccountSyncStep("加载原神角色") {
            try await bindingClient.loadGenshinRoles(secrets: secrets)
        }
        guard let role = roles.first else {
            throw AccountSessionError.missingRole
        }

        let account = await refreshedAccountProfile(
            MiHoYoAccount(
                accountID: secrets.stuid,
                mid: secrets.mid,
                nickname: result.userInfo?.nickname
            )
        )
        let summary = try await runAccountSyncStep("刷新签到状态") {
            try await signInClient.loadSummary(role: role, secrets: secrets)
        }
        let metadata = AccountMetadata(account: account, selectedRole: role, lastSummary: summary)

        try secretStore.save(secrets, accountID: account.accountID)
        do {
            try metadataStore.save(metadata)
        } catch {
            try secretStore.delete(accountID: account.accountID)
            throw error
        }

        return Self.status(from: metadata)
    }

    private func runAccountSyncStep<T: Sendable>(_ name: String, operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AccountSessionError {
            throw AccountSessionError.stepFailed(name, error.localizedDescription)
        } catch {
            throw AccountSessionError.stepFailed(name, error.localizedDescription)
        }
    }

    func completeQrLogin(ticket: String) async throws -> LocalAccountStatus {
        let result = try await queryQrLoginResult(ticket: ticket)
        return try await completeQrLogin(result: result)
    }

    func refreshSignInStatus() async throws -> LocalAccountStatus {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        let secrets = try requireSecrets(metadata)
        let summary = try await signInClient.loadSummary(role: role, secrets: secrets)
        let account = await refreshedAccountProfile(metadata.account)
        let updated = AccountMetadata(account: account, selectedRole: role, lastSummary: summary)
        try metadataStore.save(updated)
        return Self.status(from: updated)
    }

    func claimDailyReward(verification: SignInVerificationResult? = nil) async throws -> LocalAccountStatus {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        let secrets = try requireSecrets(metadata)
        let result = try await signInClient.claim(role: role, secrets: secrets, verification: verification)
        try Self.validateClaimResult(result)
        let status = try await refreshSignInStatus()
        guard status.signInSummary?.isTodaySigned == true else {
            throw AccountSessionError.invalidResponse("签到状态未确认成功")
        }
        return status
    }

    func loadResignInfo() async throws -> SignInResignInfoPayload {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        let secrets = try requireSecrets(metadata)
        return try await signInClient.loadResignInfo(role: role, secrets: secrets)
    }

    func claimResignReward(verification: SignInVerificationResult? = nil) async throws -> LocalAccountStatus {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        let secrets = try requireSecrets(metadata)
        let result = try await signInClient.resign(role: role, secrets: secrets, verification: verification)
        try Self.validateClaimResult(result)
        let status = try await refreshSignInStatus()
        let refreshedInfo = try await signInClient.loadResignInfo(role: role, secrets: secrets)
        guard refreshedInfo.signed else {
            throw AccountSessionError.invalidResponse("补签状态未确认成功")
        }
        return status
    }

    func refreshLoginTokens() async throws -> LocalAccountStatus {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        var secrets = try requireSecrets(metadata)
        secrets = try await passportClient.refreshLToken(secrets: secrets)
        secrets = try await passportClient.refreshCookieToken(secrets: secrets)

        let summary = try await signInClient.loadSummary(role: role, secrets: secrets)
        let account = await refreshedAccountProfile(metadata.account)
        let updated = AccountMetadata(account: account, selectedRole: role, lastSummary: summary)
        try secretStore.save(secrets, accountID: metadata.account.accountID)
        try metadataStore.save(updated)
        return Self.status(from: updated)
    }

    func signInWebVerificationContext() throws -> SignInWebVerificationContext {
        let metadata = try requireMetadata()
        let secrets = try requireSecrets(metadata)
        guard let cookieToken = secrets.cookieToken, !cookieToken.isEmpty else {
            throw AccountSessionError.missingAccount
        }
        return SignInWebVerificationContext(
            url: HoYoConstants.signInVerificationURL,
            accountID: metadata.account.accountID,
            mid: metadata.account.mid,
            nickname: metadata.account.nickname,
            avatarURL: metadata.account.avatarURL,
            cookieToken: cookieToken,
            ltoken: secrets.ltoken,
            selectedRole: metadata.selectedRole
        )
    }

    func loadGachaRecords() async throws -> [GachaRecord] {
        let metadata = try requireMetadata()
        let role = try requireRole(metadata)
        let secrets = try requireSecrets(metadata)
        return try await gachaLogClient.loadRecords(role: role, secrets: secrets)
    }

    func signOut() throws -> LocalAccountStatus {
        let accountID = try metadataStore.load()?.account.accountID
        if let accountID, try secretStore.load(accountID: accountID) != nil {
            try secretStore.delete(accountID: accountID)
        }
        try metadataStore.clear()
        return .signedOut
    }

    nonisolated static func status(from metadata: AccountMetadata) -> LocalAccountStatus {
        LocalAccountStatus(
            isSignedIn: true,
            nickname: metadata.account.nickname,
            avatarURL: metadata.account.avatarURL,
            accountID: metadata.account.accountID,
            selectedRole: metadata.selectedRole,
            signInSummary: metadata.lastSummary,
            sessionMessage: nil,
            lastCheckInDate: metadata.lastSummary.flatMap { summary in
                guard summary.isTodaySigned, let serverDate = summary.serverDate else { return nil }
                return Self.serverDateFormatter.date(from: serverDate)
            }
        )
    }

    nonisolated private static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated static func validateClaimResult(_ result: SignInResultPayload) throws {
        let needsVerification = result.riskCode == -5003
            || result.isRisk == true
            || result.success == 1
            || result.gt != nil
            || result.challenge != nil
        if needsVerification {
            throw AccountSessionError.requiresVerification(result)
        }

        let code = result.code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard result.success == 0 || code == "ok" else {
            throw AccountSessionError.invalidResponse("签到接口未明确确认成功")
        }
    }

    private func requireMetadata() throws -> AccountMetadata {
        guard let metadata = try metadataStore.load() else {
            throw AccountSessionError.missingAccount
        }
        return metadata
    }

    private func requireRole(_ metadata: AccountMetadata) throws -> GenshinRole {
        guard let role = metadata.selectedRole else {
            throw AccountSessionError.missingRole
        }
        return role
    }

    private func requireSecrets(_ metadata: AccountMetadata) throws -> AccountSecrets {
        guard let secrets = try secretStore.load(accountID: metadata.account.accountID) else {
            throw AccountSessionError.missingAccount
        }
        return secrets
    }

    private func refreshedAccountProfile(_ account: MiHoYoAccount) async -> MiHoYoAccount {
        do {
            let profile = try await userClient.loadUserProfile(accountID: account.accountID)
            var updated = account
            if let nickname = profile.nickname, !nickname.isEmpty {
                updated.nickname = nickname
            }
            if let avatarURL = profile.avatarURL {
                updated.avatarURL = avatarURL
            }
            return updated
        } catch {
            return account
        }
    }

    private static func makeDefaultMetadataStore() -> AccountMetadataStoring {
        do {
            let store = try LocalAccountMetadataStore()
            return store
        } catch {
            return UnavailableAccountMetadataStore(error: storageUnavailableError(error))
        }
    }

    private static func makeDefaultSecretStore() -> AccountSecretStoring {
        do {
            let store = try LocalAccountSecretStore()
            return store
        } catch {
            return UnavailableAccountSecretStore(error: storageUnavailableError(error))
        }
    }

    private static func storageUnavailableError(_ error: Error) -> AccountSessionError {
        if let accountError = error as? AccountSessionError {
            return accountError
        }
        let message = error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
        return AccountSessionError.localStorageUnavailable(message)
    }
}

private struct UnavailableAccountMetadataStore: AccountMetadataStoring {
    var error: AccountSessionError

    func load() throws -> AccountMetadata? {
        throw error
    }

    func save(_ metadata: AccountMetadata) throws {
        throw error
    }

    func clear() throws {
        throw error
    }
}

private struct UnavailableAccountSecretStore: AccountSecretStoring {
    var error: AccountSessionError

    func load(accountID: String) throws -> AccountSecrets? {
        throw error
    }

    func save(_ secrets: AccountSecrets, accountID: String) throws {
        throw error
    }

    func delete(accountID: String) throws {
        throw error
    }
}
