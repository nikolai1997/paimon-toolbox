import SwiftUI

struct OverviewView: View {
    @Bindable var store: AppStore

    private var activeGachaEvents: [GachaEventInfo] {
        OverviewSummary.activeGachaEvents(from: store.overviewData.gachaEvents)
    }

    private var planHighlights: [OverviewPlanHighlight] {
        OverviewSummary.planHighlights(from: store.plans)
    }

    private var gachaAnalysis: GachaAnalysis {
        GachaAnalysis.make(from: store.activeGachaRecords)
    }

    private var characterRerunTimers: [RerunTimerEntry] {
        OverviewSummary.characterRerunTimers(
            from: store.overviewData.gachaEvents,
            characters: store.metadata?.characters ?? [],
            limit: 200
        )
    }

    private var weaponRerunTimers: [RerunTimerEntry] {
        OverviewSummary.weaponRerunTimers(
            from: store.overviewData.gachaEvents,
            weapons: store.metadata?.weapons ?? [],
            limit: 200
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OverviewHero(store: store)
                overviewMetrics

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                    CurrentGachaEventsPanel(events: activeGachaEvents) {
                        store.selectedSection = .gachaLog
                    }

                    RerunTimerPanel(
                        characterEntries: characterRerunTimers,
                        weaponEntries: weaponRerunTimers
                    )

                    GachaSummaryPanel(summary: store.gachaSummary, analysis: gachaAnalysis) {
                        store.selectedSection = .gachaLog
                    }

                    SignInStatusPanel(status: store.accountStatus, isBusy: store.isAccountBusy) {
                        store.selectedSection = .account
                    }

                    PlanSummaryPanel(planCount: store.plans.count, highlights: planHighlights) {
                        store.selectedSection = .planner
                    }

                    AnnouncementPanel(items: store.overviewData.announcements)
                }

                if let error = store.errorMessage {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .glassPanel(cornerRadius: 18)
                }

                Spacer(minLength: 0)
            }
            .glassPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.clear)
    }

    private var overviewMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            GlassMetricCard(title: "祈愿记录", value: "\(store.gachaSummary.totalPulls) 抽", systemImage: "sparkles", tint: .orange)
            GlassMetricCard(title: "活动池垫数", value: "\(store.gachaSummary.activityPity) 抽", systemImage: "person.crop.circle.badge.clock", tint: .blue)
            GlassMetricCard(title: "常驻池垫数", value: "\(store.gachaSummary.standardPity) 抽", systemImage: "clock", tint: .green)
            GlassMetricCard(title: "五星", value: "\(store.gachaSummary.fiveStarCount) 个", systemImage: "star", tint: .yellow)
            GlassMetricCard(title: "养成计划", value: "\(store.plans.count)", systemImage: "checklist", tint: .green)
            GlassMetricCard(title: "签到", value: signInMetricValue, systemImage: "checkmark.seal", tint: .mint)
        }
    }

    private var signInMetricValue: String {
        guard store.accountStatus.isSignedIn else {
            return "未登录"
        }

        return store.accountStatus.signInSummary?.isTodaySigned == true ? "已签到" : "待签到"
    }
}

private struct OverviewHero: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("派蒙工具箱")
                    .font(.largeTitle.bold())
                Text(heroSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                Button {
                    store.selectedSection = .database
                } label: {
                    Label("资料库", systemImage: "books.vertical")
                }

                Button {
                    store.selectedSection = .gachaLog
                } label: {
                    Label("祈愿", systemImage: "sparkles")
                }

                Button {
                    store.selectedSection = .planner
                } label: {
                    Label("计划", systemImage: "checklist")
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .glassPanel(cornerRadius: 18)
    }

    private var heroSubtitle: String {
        if store.accountStatus.signInSummary?.isTodaySigned == true {
            return "今日已签到，资料库、卡池和养成进度都已就位。"
        }
        return "资料库、祈愿记录和养成计划都保存在这台 Mac。"
    }
}

private struct CurrentGachaEventsPanel: View {
    var events: [GachaEventInfo]
    var openGachaLog: () -> Void
    @State private var selectedEvent: GachaEventInfo?

    var body: some View {
        OverviewPanel(title: "当前卡池", systemImage: "sparkles", actionTitle: "祈愿记录", action: openGachaLog) {
            if events.isEmpty {
                OverviewEmptyState(title: "暂无进行中的卡池", detail: "数据更新后会自动显示", systemImage: "calendar.badge.exclamationmark")
            } else {
                VStack(spacing: 12) {
                    ForEach(events.prefix(3)) { event in
                        Button {
                            selectedEvent = event
                        } label: {
                            HStack(spacing: 12) {
                                GachaEventBanner(url: event.bannerURL)
                                    .frame(width: 86, height: 48)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("\(event.typeTitle) · \(event.version)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(eventDateRange(event))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .popover(item: $selectedEvent, arrowEdge: .trailing) { event in
            GachaEventDetailSheet(event: event)
        }
    }

    private func eventDateRange(_ event: GachaEventInfo) -> String {
        "\(event.from.formatted(.dateTime.month().day().hour().minute())) - \(event.to.formatted(.dateTime.month().day().hour().minute()))"
    }
}

private struct GachaEventBanner: View {
    var url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct GachaEventDetailSheet: View {
    var event: GachaEventInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GachaEventBanner(url: event.bannerURL)
                .aspectRatio(2.4, contentMode: .fit)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.name)
                    .font(.title.bold())
                Text("\(event.typeTitle) · \(event.version)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(event.from.formatted(.dateTime.year().month().day().hour().minute())) - \(event.to.formatted(.dateTime.year().month().day().hour().minute()))")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 430)
    }
}

private struct RerunTimerPanel: View {
    var characterEntries: [RerunTimerEntry]
    var weaponEntries: [RerunTimerEntry]
    @State private var isShowingAll = false

    var body: some View {
        OverviewPanel(title: "复刻计时器", systemImage: "hourglass", actionTitle: "全部") {
            isShowingAll = true
        } content: {
            if characterEntries.isEmpty && weaponEntries.isEmpty {
                OverviewEmptyState(title: "暂无复刻记录", detail: "卡池历史加载后会自动计算", systemImage: "hourglass")
            } else {
                HStack(alignment: .top, spacing: 18) {
                    RerunTimerSection(title: "角色", entries: Array(characterEntries.prefix(5)))
                    Divider().opacity(0.45)
                    RerunTimerSection(title: "武器", entries: Array(weaponEntries.prefix(5)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isShowingAll = true
        }
        .popover(isPresented: $isShowingAll, arrowEdge: .trailing) {
            RerunTimerDetailPopover(
                characterEntries: characterEntries,
                weaponEntries: weaponEntries
            )
        }
    }
}

private struct RerunTimerSection: View {
    var title: String
    var entries: [RerunTimerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        RerunTimerRow(entry: entry)
                    }
                }
            }
        }
    }
}

private struct RerunTimerRow: View {
    var entry: RerunTimerEntry

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RerunTimerIcon(url: entry.iconURL, kind: entry.kind)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("上次 \(entry.version) · \(entry.lastBannerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(entry.daysText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(entry.daysSinceLastAppearance == 0 ? .green : .primary)
                .lineLimit(1)
        }
    }
}

private struct RerunTimerIcon: View {
    var url: URL?
    var kind: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            default:
                Image(systemName: kind == "weapon" ? "wand.and.stars" : "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RerunTimerDetailPopover: View {
    var characterEntries: [RerunTimerEntry]
    var weaponEntries: [RerunTimerEntry]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                RerunTimerSection(title: "角色", entries: characterEntries)
                Divider().opacity(0.45)
                RerunTimerSection(title: "武器", entries: weaponEntries)
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct GachaSummaryPanel: View {
    var summary: GachaSummary
    var analysis: GachaAnalysis
    var openGachaLog: () -> Void

    var body: some View {
        OverviewPanel(title: "祈愿摘要", systemImage: "chart.bar.xaxis", actionTitle: summary.totalPulls == 0 ? "去同步" : "详情", action: openGachaLog) {
            if summary.totalPulls == 0 {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("祈愿记录待同步")
                                .font(.title3.weight(.semibold))
                            Text("同步后会显示垫数、五星出率和最近五星。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 12) {
                        OverviewInlineMetric(title: "总抽数", value: "-- 抽")
                        OverviewInlineMetric(title: "当前垫数", value: "-- 抽")
                        OverviewInlineMetric(title: "五星出率", value: "--")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        OverviewInlineMetric(title: "活动池垫数", value: "\(summary.activityPity) 抽")
                        OverviewInlineMetric(title: "常驻池垫数", value: "\(summary.standardPity) 抽")
                        OverviewInlineMetric(title: "五星出率", value: analysis.fiveStarRateText)
                        OverviewInlineMetric(title: "平均间隔", value: averageFiveStarPityText)
                    }

                    if let recent = analysis.recentFiveStars.first {
                        Label("\(recent.name) · \(recent.pullsSincePreviousFiveStar) 抽 · \(recent.banner.title)", systemImage: "clock.badge.checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
    }

    private var averageFiveStarPityText: String {
        guard analysis.averageFiveStarPityText != "--" else {
            return "-- 抽"
        }

        return analysis.averageFiveStarPityText
    }
}

private struct SignInStatusPanel: View {
    var status: LocalAccountStatus
    var isBusy: Bool
    var openAccount: () -> Void

    var body: some View {
        OverviewPanel(title: "签到", systemImage: "checkmark.seal", actionTitle: "账号", action: openAccount) {
            if status.isSignedIn {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(status.signInSummary?.isTodaySigned == true ? "已签到" : "待签到")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(status.nickname ?? status.selectedRole?.nickname ?? "已登录账号")
                        .foregroundStyle(.secondary)
                    if let summary = status.signInSummary {
                        HStack(spacing: 14) {
                            OverviewInlineMetric(title: "本月", value: "\(summary.totalSignDay) 天")
                            OverviewInlineMetric(title: "月份", value: "\(summary.month) 月")
                            OverviewInlineMetric(title: "UID", value: summary.uid)
                        }
                    }
                }
            } else {
                OverviewEmptyState(title: "未登录账号", detail: "扫码后可查看签到状态", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
    }
}

private struct PlanSummaryPanel: View {
    var planCount: Int
    var highlights: [OverviewPlanHighlight]
    var openPlanner: () -> Void

    var body: some View {
        OverviewPanel(title: "养成进度", systemImage: "checklist", actionTitle: "计划", action: openPlanner) {
            if planCount == 0 {
                OverviewEmptyState(title: "暂无养成计划", detail: "选择角色或武器后开始", systemImage: "checklist")
            } else if highlights.isEmpty {
                OverviewEmptyState(title: "计划已完成", detail: "所有材料都已准备好", systemImage: "checkmark.circle")
            } else {
                VStack(spacing: 12) {
                    ForEach(highlights) { highlight in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(highlight.targetName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text(highlight.completionText)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            ProgressView(value: highlight.completion)
                        }
                    }
                }
            }
        }
    }
}

private struct AnnouncementPanel: View {
    var items: [AnnouncementItem]
    @State private var selectedItem: AnnouncementItem?

    var body: some View {
        OverviewPanel(title: "近期公告", systemImage: "megaphone", actionTitle: nil, action: nil) {
            if items.isEmpty {
                OverviewEmptyState(title: "暂无公告", detail: "公告源接入后显示", systemImage: "megaphone")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items.prefix(3)) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .popover(item: $selectedItem, arrowEdge: .trailing) { item in
            AnnouncementDetailSheet(item: item)
        }
    }
}

private struct AnnouncementDetailSheet: View {
    var item: AnnouncementItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if item.bannerURL != nil {
                GachaEventBanner(url: item.bannerURL)
                    .aspectRatio(2.4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.title.bold())
                if let typeLabel = item.typeLabel, !typeLabel.isEmpty {
                    Text(typeLabel)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                if let dateRange {
                    Text(dateRange)
                        .foregroundStyle(.secondary)
                }
            }

            if let url = item.url {
                Link(destination: url) {
                    Label("打开原文", systemImage: "safari")
                }
                .controlSize(.large)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
    }

    private var dateRange: String? {
        guard let startsAt = item.startsAt, let endsAt = item.endsAt else {
            return nil
        }

        return "\(startsAt.formatted(.dateTime.year().month().day().hour().minute())) - \(endsAt.formatted(.dateTime.year().month().day().hour().minute()))"
    }
}

private struct OverviewPanel<Content: View>: View {
    var title: String
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.borderless)
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }
}

private struct OverviewInlineMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72, alignment: .leading)
    }
}

private struct OverviewEmptyState: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    }
}
