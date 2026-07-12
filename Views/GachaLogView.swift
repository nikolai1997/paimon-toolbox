import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct GachaLogView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GachaLogHeader(store: store, importRecords: importRecords, exportRecords: exportRecords)
                .padding(.horizontal, 24)
                .padding(.top, 20)

            if store.activeGachaRecords.isEmpty {
                ContentUnavailableView("暂无祈愿记录", systemImage: "sparkles", description: Text("会优先读取本机已保存的祈愿记录；没有本地记录时，可从账号更新或导入 UIGF JSON。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GachaAnalysisDashboard(records: store.activeGachaRecords)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(.clear)
    }

    private func importRecords() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await store.importGachaRecords(from: url)
            }
        }
    }

    private func exportRecords() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "genshin-gacha-uigf.json"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await store.exportGachaRecords(to: url)
            }
        }
    }
}

private struct GachaLogHeader: View {
    @Bindable var store: AppStore
    var importRecords: () -> Void
    var exportRecords: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                    GlassMetricCard(title: "总抽数", value: "\(store.gachaSummary.totalPulls)", systemImage: "number")
                    GlassMetricCard(title: "五星", value: "\(store.gachaSummary.fiveStarCount)", systemImage: "star.fill", tint: .orange)
                    GlassMetricCard(title: "四星", value: "\(store.gachaSummary.fourStarCount)", systemImage: "star.leadinghalf.filled", tint: .purple)
                    GlassMetricCard(title: "活动池垫数", value: "\(store.gachaSummary.activityPity)", systemImage: "person.crop.circle.badge.clock", tint: .green)
                    GlassMetricCard(title: "常驻池垫数", value: "\(store.gachaSummary.standardPity)", systemImage: "clock", tint: .blue)
                }
                .frame(maxWidth: 680, alignment: .leading)

                Spacer(minLength: 16)

                HStack {
                    if store.availableGachaUIDs.count + (store.hasUnassignedGachaRecords ? 1 : 0) > 1 {
                        Picker("记录账号", selection: Binding(
                            get: { store.activeGachaUID },
                            set: { store.selectGachaUID($0) }
                        )) {
                            ForEach(store.availableGachaUIDs, id: \.self) { uid in
                                Text("UID \(uid)").tag(Optional(uid))
                            }
                            if store.hasUnassignedGachaRecords {
                                Text("未归属记录").tag(String?.none)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                    }

                    Button {
                        Task {
                            await store.syncGachaRecordsFromAccount()
                        }
                    } label: {
                        Label("从账号更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!store.accountStatus.isSignedIn || store.isAccountBusy)

                    Button {
                        importRecords()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportRecords()
                    } label: {
                        Label("导出当前账号 UIGF", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.activeGachaRecords.isEmpty)
                }
                .controlSize(.large)
            }

            if let message = store.successMessage {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            Label(gachaFreshnessText, systemImage: "clock.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .glassPanel(cornerRadius: 18)
    }

    private var gachaFreshnessText: String {
        guard let latestTime = store.activeGachaRecords.map(\.time).max() else {
            return "本机暂无已保存记录；从账号更新只会获取官方祈愿历史接口已开放的数据。"
        }

        return "本地最新记录：\(latestTime.formatted(date: .numeric, time: .shortened))。官方祈愿历史通常有延迟，刚抽卡不会立刻出现在记录中。"
    }
}

private struct GachaAnalysisDashboard: View {
    let records: [GachaRecord]
    @AppStorage("gacha.dashboard.moduleOrder") private var storedModuleOrder = ""
    @State private var isRecordDetailsExpanded = false
    @State private var draggedModule: GachaDashboardModule?
    @State private var activeDropTarget: GachaDashboardModule?

    private var analysis: GachaAnalysis {
        GachaAnalysis.make(from: records)
    }

    private var moduleOrder: [GachaDashboardModule] {
        GachaDashboardLayout.modules(from: storedModuleOrder)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
            ForEach(moduleOrder) { module in
                dashboardModule(module)
                    .frame(maxWidth: .infinity, minHeight: 238, alignment: .topLeading)
                    .dashboardDragHandle(module: module)
                    .opacity(draggedModule == module ? 0.42 : 1)
                    .scaleEffect(draggedModule == module ? 0.98 : 1)
                    .onDrag {
                        draggedModule = module
                        return NSItemProvider(object: module.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: GachaDashboardModuleDropDelegate(
                            target: module,
                            draggedModule: $draggedModule,
                            activeDropTarget: $activeDropTarget,
                            moveModule: moveModule
                        )
                    )
            }
        }
        .animation(.snappy(duration: 0.22), value: storedModuleOrder)
        .animation(.snappy(duration: 0.16), value: draggedModule)
        .onDrop(
            of: [UTType.text],
                    delegate: GachaDashboardGridDropDelegate(
                draggedModule: $draggedModule,
                activeDropTarget: $activeDropTarget,
                moveModuleToEnd: moveModuleToEnd
            )
        )
    }

    @ViewBuilder
    private func dashboardModule(_ module: GachaDashboardModule) -> some View {
        switch module {
        case .insights:
            GachaChartPanel(title: "抽卡洞察", systemImage: "chart.bar.fill") {
                VStack(spacing: 10) {
                    GachaInsightMetric(
                        title: "五星出率",
                        value: analysis.fiveStarRateText,
                        detail: "共 \(analysis.rarityBreakdown.first { $0.rarity == 5 }?.count ?? 0) 个五星",
                        systemImage: "sparkles",
                        tint: .orange
                    )
                    GachaInsightMetric(
                        title: "四星出率",
                        value: analysis.fourStarRateText,
                        detail: "共 \(analysis.rarityBreakdown.first { $0.rarity == 4 }?.count ?? 0) 个四星",
                        systemImage: "star.leadinghalf.filled",
                        tint: .purple
                    )
                    GachaInsightMetric(
                        title: "平均五星间隔",
                        value: analysis.averageFiveStarPityText,
                        detail: "按各卡池独立统计",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                        tint: .pink
                    )
                    GachaInsightMetric(
                        title: "最近五星",
                        value: analysis.recentFiveStars.first?.name ?? "--",
                        detail: analysis.recentFiveStars.first.map { "\($0.pullsSincePreviousFiveStar) 抽 · \($0.banner.title)" } ?? "暂无五星记录",
                        systemImage: "clock.badge.checkmark",
                        tint: .green
                    )
                }
            }
        case .rarityDistribution:
            GachaChartPanel(title: "星级分布", systemImage: "chart.bar.xaxis") {
                RarityBreakdownChart(items: analysis.rarityBreakdown)
            }
        case .bannerDistribution:
            GachaChartPanel(title: "卡池占比", systemImage: "rectangle.3.group") {
                BannerBreakdownChart(items: analysis.bannerBreakdown)
            }
        case .monthlyTrend:
            GachaChartPanel(title: "月度抽取走势", systemImage: "chart.xyaxis.line") {
                MonthlyTrendChart(items: analysis.monthlyTrend)
            }
        case .bannerPity:
            GachaChartPanel(title: "卡池状态", systemImage: "timer") {
                BannerPitySummary(stats: analysis.bannerStats)
            }
        case .recentFiveStars:
            GachaChartPanel(title: "五星轨迹", systemImage: "sparkle.magnifyingglass") {
                RecentFiveStarList(items: analysis.recentFiveStars)
            }
        case .recordDetails:
            GachaRecordTable(records: records, isExpanded: $isRecordDetailsExpanded)
        }
    }

    private func moveModule(_ dragged: GachaDashboardModule, before target: GachaDashboardModule) {
        let moved = GachaDashboardLayout.move(dragged, before: target, in: moduleOrder)
        storedModuleOrder = GachaDashboardLayout.encoded(moved)
    }

    private func moveModuleToEnd(_ dragged: GachaDashboardModule) {
        let moved = GachaDashboardLayout.moveToEnd(dragged, in: moduleOrder)
        storedModuleOrder = GachaDashboardLayout.encoded(moved)
    }
}

private struct GachaDashboardModuleDropDelegate: DropDelegate {
    let target: GachaDashboardModule
    @Binding var draggedModule: GachaDashboardModule?
    @Binding var activeDropTarget: GachaDashboardModule?
    var moveModule: (GachaDashboardModule, GachaDashboardModule) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedModule != nil
    }

    func dropEntered(info: DropInfo) {
        guard
            let draggedModule,
            draggedModule != target,
            activeDropTarget != target
        else {
            return
        }

        activeDropTarget = target
        withAnimation(.snappy(duration: 0.18)) {
            moveModule(draggedModule, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        activeDropTarget = nil
        draggedModule = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if activeDropTarget == target {
            activeDropTarget = nil
        }
    }
}

private struct GachaDashboardGridDropDelegate: DropDelegate {
    @Binding var draggedModule: GachaDashboardModule?
    @Binding var activeDropTarget: GachaDashboardModule?
    var moveModuleToEnd: (GachaDashboardModule) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedModule != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard activeDropTarget == nil else {
            activeDropTarget = nil
            draggedModule = nil
            return true
        }

        if let draggedModule {
            withAnimation(.snappy(duration: 0.18)) {
                moveModuleToEnd(draggedModule)
            }
        }
        activeDropTarget = nil
        draggedModule = nil
        return true
    }
}

private struct GachaDashboardDragHandle: ViewModifier {
    let module: GachaDashboardModule

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(10)
                    .help("拖拽调整模块位置")
            }
    }
}

private extension View {
    func dashboardDragHandle(module: GachaDashboardModule) -> some View {
        modifier(GachaDashboardDragHandle(module: module))
    }
}

private struct GachaInsightTile: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 96, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanel(cornerRadius: 16)
    }
}

private struct GachaInsightMetric: View {
    var title: String
    var value: String
    var detail: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GachaChartPanel<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }
}

private struct RarityBreakdownChart: View {
    let items: [GachaRarityBreakdown]

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("数量", item.count),
                y: .value("星级", item.title)
            )
            .foregroundStyle(item.rarity.analysisColor)
            .annotation(position: .trailing) {
                Text("\(item.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartLegend(.hidden)
        .frame(height: 170)
    }
}

private struct BannerBreakdownChart: View {
    let items: [GachaBannerBreakdown]

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("抽数", item.count),
                y: .value("卡池", item.banner.shortTitle)
            )
            .foregroundStyle(item.banner.analysisColor)
            .annotation(position: .trailing) {
                Text("\(item.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartLegend(.hidden)
        .frame(height: 170)
    }
}

private struct MonthlyTrendChart: View {
    let items: [GachaMonthlyTrend]

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("月份", item.monthLabel),
                y: .value("总抽数", item.count)
            )
            .foregroundStyle(Color.accentColor.opacity(0.58))

            LineMark(
                x: .value("月份", item.monthLabel),
                y: .value("五星", item.fiveStarCount)
            )
            .foregroundStyle(.orange)
            .symbol {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 220)
    }
}

private struct BannerPitySummary: View {
    let stats: [GachaBannerStat]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(stats) { stat in
                HStack(alignment: .top) {
                    Circle()
                        .fill(stat.banner.analysisColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.banner.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(stat.count) 抽 · \(stat.fiveStarCount) 个五星 · \(stat.fourStarCount) 个四星")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(stat.currentPity)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("当前垫数")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minHeight: 180, alignment: .top)
    }
}

private struct RecentFiveStarList: View {
    let items: [GachaFiveStarHit]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView("暂无五星记录", systemImage: "star", description: Text("更新或导入更多记录后会展示五星轨迹。"))
                .frame(minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.banner.analysisColor)
                            .frame(width: 4, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(item.banner.shortTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(item.pullsSincePreviousFiveStar) 抽")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            Text(item.time.formatted(date: .numeric, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 180, alignment: .top)
        }
    }
}

private struct GachaRecordTable: View {
    let records: [GachaRecord]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Table(records) {
                TableColumn("时间") { record in
                    Text(record.time.formatted(date: .numeric, time: .shortened))
                }
                TableColumn("卡池") { record in
                    Text(record.banner.title)
                }
                TableColumn("名称") { record in
                    Text(record.name)
                }
                TableColumn("类型") { record in
                    Text(record.itemType)
                }
                TableColumn("星级") { record in
                    Text("\(record.rarity)")
                        .foregroundStyle(record.rarity.analysisColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(minHeight: 340)
            .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Label("记录明细", systemImage: "list.bullet.rectangle")
                    .font(.headline.weight(.semibold))

                Spacer()

                Text("\(records.count) 条")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 18)
    }
}

private extension BannerKind {
    var shortTitle: String {
        switch self {
        case .character:
            "角色"
        case .characterEvent2:
            "角色2"
        case .weapon:
            "武器"
        case .chronicled:
            "集录"
        case .standard:
            "常驻"
        }
    }

    var analysisColor: Color {
        switch self {
        case .character:
            .blue
        case .characterEvent2:
            .cyan
        case .weapon:
            .pink
        case .chronicled:
            .indigo
        case .standard:
            .green
        }
    }
}

private extension Int {
    var analysisColor: Color {
        switch self {
        case 5:
            .orange
        case 4:
            .purple
        default:
            .secondary
        }
    }
}
