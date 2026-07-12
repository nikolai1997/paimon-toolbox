import Foundation
import SwiftUI

struct AccountView: View {
    @Bindable var store: AppStore

    @State private var isPresentingQRSheet = false
    @State private var isPresentingVerificationSheet = false
    @State private var isConfirmingResign = false

    private let rewardColumns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    messageSection

                    if store.accountStatus.isSignedIn {
                        signedInWorkspace
                    } else {
                        signedOutWorkspace
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPagePadding()
                .padding(.bottom, store.accountStatus.isSignedIn ? 112 : 0)
            }

            if store.accountStatus.isSignedIn {
                actionRow
                    .accessibilityIdentifier("account-floating-action-bar")
                    .padding(.trailing, 28)
                    .padding(.bottom, 28)
            }
        }
        .background(.clear)
        .sheet(isPresented: $isPresentingQRSheet) {
            QRCodeLoginSheet(store: store)
        }
        .sheet(isPresented: $isPresentingVerificationSheet) {
            if let verification = store.accountVerification {
                verificationSheet(verification)
            }
        }
        .confirmationDialog(
            "确认补签",
            isPresented: $isConfirmingResign,
            titleVisibility: .visible
        ) {
            Button("确认补签", role: .destructive) {
                Task { await store.claimResignReward() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(resignConfirmationMessage)
        }
        .onChange(of: store.confirmedQrLoginSessionID) { _, sessionID in
            guard let sessionID else { return }
            Task { await store.finishConfirmedQrLogin(sessionID: sessionID) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("账号与签到")
                .font(.largeTitle.bold())
            Text("使用米游社扫码登录，登录态加密保存到这台 Mac 的本机文件中。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassPanel(cornerRadius: 18)
    }

    @ViewBuilder
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let success = store.successMessage, !success.isEmpty {
                statusBanner(text: success, systemImage: "checkmark.circle.fill", tint: .green)
            }

            if let error = store.errorMessage, !error.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        statusBanner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)

                        if verificationURL != nil {
                            Button {
                                isPresentingVerificationSheet = true
                            } label: {
                                Label("打开验证", systemImage: "network")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if shouldShowVerificationHint {
                        Text("请点击打开验证，在内嵌米游社页面完成安全验证或签到后，再刷新状态。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
            }

            if store.canRetryConfirmedQrLoginSync {
                Button {
                    Task { await store.retryConfirmedQrLoginSync() }
                } label: {
                    Label("重试同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isAccountBusy)
            }
        }
    }

    private var signedOutWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            ContentUnavailableView(
                "未登录米游社账号",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("扫码后即可同步当前角色签到状态，登录凭据加密保存到本机文件。")
            )
            .frame(maxWidth: .infinity)

            Button {
                isPresentingQRSheet = true
                Task { await store.startQrLogin() }
            } label: {
                Label("扫码登录", systemImage: "qrcode")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isAccountBusy)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassPanel(cornerRadius: 18)
    }

    private var signedInWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            accountSummary

            if let summary = store.accountStatus.signInSummary {
                signInSummary(summary)
                rewardGrid(summary.rewards)
            }
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                accountAvatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(store.accountStatus.nickname ?? "已登录账号")
                            .font(.title2.bold())
                        if store.isAccountBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let roleName = store.accountStatus.selectedRole?.nickname, !roleName.isEmpty {
                        Text(roleName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    infoMetric("UID", store.accountStatus.selectedRole?.uid ?? "--")
                    infoMetric("服务器", store.accountStatus.selectedRole?.region ?? "--")
                    infoMetric("等级", store.accountStatus.selectedRole.map { "Lv.\($0.level)" } ?? "--")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private var accountAvatar: some View {
        Group {
            if let avatarURL = store.accountStatus.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        accountAvatarPlaceholder
                    }
                }
            } else {
                accountAvatarPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var accountAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
        }
    }

    private func signInSummary(_ summary: SignInSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("签到概览")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                GridRow {
                    infoMetric("本月累计", "\(summary.totalSignDay) 天")
                    infoMetric("签到月份", "\(summary.month) 月")
                    infoMetric("今日状态", summary.isTodaySigned ? "已签到" : "待签到")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }

    private func rewardGrid(_ rewards: [SignInReward]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("奖励日历")
                .font(.headline)

            LazyVGrid(columns: rewardColumns, alignment: .leading, spacing: 12) {
                ForEach(rewards) { reward in
                    rewardTile(reward)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.claimDailyReward() }
            } label: {
                Label("立即签到", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .disabled((store.accountStatus.signInSummary?.isTodaySigned ?? false) || store.isAccountBusy)

            if let resignInfo = store.accountResignInfo, resignInfo.signCountMissed > 0 {
                Button {
                    isConfirmingResign = true
                } label: {
                    Label("补签", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!resignInfo.canResign || store.isAccountBusy)
                .help(resignHelpText(resignInfo))
            }

            Button {
                Task { await store.refreshSignInStatus() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(store.isAccountBusy)

            Button(role: .destructive) {
                store.signOutAccount()
            } label: {
                Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .disabled(store.isAccountBusy)
        }
        .controlSize(.large)
        .padding(14)
        .glassPanel(cornerRadius: 16)
    }

    private func infoMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 140, alignment: .leading)
    }

    private func rewardTile(_ reward: SignInReward) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                rewardIcon(for: reward)
                    .frame(width: 36, height: 36)

                Spacer(minLength: 8)

                Text("第\(reward.day)天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reward.isClaimed ? Color.green : Color.secondary)
            }

            Text(reward.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("x\(reward.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(reward.isClaimed ? Color.green.opacity(0.12) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func rewardIcon(for reward: SignInReward) -> some View {
        if let url = reward.iconURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "gift")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        } else {
            Image(systemName: "gift")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private func statusBanner(text: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }

    private func verificationSheet(_ verification: AccountVerificationState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("安全验证")
                        .font(.headline)
                    Text(verification.webContext != nil || verification.payload?.gt == nil ? "正在使用内嵌米游社页面完成安全验证。" : "完成验证后会自动重试签到。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresentingVerificationSheet = false
                } label: {
                    Label("关闭", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)

            Divider()

            if let payload = verification.payload, payload.gt != nil || verification.webContext != nil {
                MiHoYoVerificationWebView(
                    payload: payload,
                    fallbackURL: verification.url,
                    webContext: verification.webContext
                ) { result in
                    isPresentingVerificationSheet = false
                    Task {
                        switch verification.purpose {
                        case .dailySignIn:
                            await store.completeSignInVerification(result)
                        case .resign:
                            await store.completeResignVerification(result)
                        }
                    }
                } onClose: {
                    isPresentingVerificationSheet = false
                    Task {
                        await store.refreshSignInStatus()
                    }
                }
                .frame(minWidth: 760, minHeight: 560)
            } else {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "无法内嵌验证",
                        systemImage: "exclamationmark.triangle",
                        description: Text("米游社这次没有返回验证参数，也缺少本地登录凭据上下文。请重新扫码登录后再试。")
                    )

                    HStack(spacing: 12) {
                        Button {
                            isPresentingVerificationSheet = false
                            Task {
                                switch verification.purpose {
                                case .dailySignIn:
                                    await store.claimDailyReward()
                                case .resign:
                                    await store.claimResignReward()
                                }
                            }
                        } label: {
                            Label("我已完成，重试签到", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            isPresentingVerificationSheet = false
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(minWidth: 560, minHeight: 360)
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }

    private var shouldShowVerificationHint: Bool {
        if store.accountVerification != nil {
            return true
        }

        let text = store.errorMessage ?? ""
        return text.contains("风控") || text.contains("验证")
    }

    private var verificationURL: URL? {
        store.accountVerification?.url
    }

    private var resignConfirmationMessage: String {
        guard let info = store.accountResignInfo else {
            return "将消耗补签资源补领最近一次漏签奖励。"
        }
        return "当前漏签 \(info.signCountMissed) 天，本次补签消耗 \(info.coinCost)，当前可用 \(info.coinCount)。今日已补 \(info.resignCountDaily)/\(info.resignLimitDaily)，本月已补 \(info.resignCountMonthly)/\(info.resignLimitMonthly)。"
    }

    private func resignHelpText(_ info: SignInResignInfoPayload) -> String {
        if info.canResign {
            return "漏签 \(info.signCountMissed) 天，补签消耗 \(info.coinCost)，当前可用 \(info.coinCount)"
        }
        if info.coinCount < info.coinCost {
            return "补签资源不足：需要 \(info.coinCost)，当前 \(info.coinCount)"
        }
        if info.resignCountDaily >= info.resignLimitDaily {
            return "今日补签次数已用完"
        }
        if info.resignCountMonthly >= info.resignLimitMonthly {
            return "本月补签次数已用完"
        }
        return "当前没有可补签日期"
    }
}
