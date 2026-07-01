import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    private var trimmedSearchText: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var globalSearchResults: [GlobalSearchResult] {
        GlobalSearchIndex.results(
            matching: store.searchText,
            metadata: store.metadata,
            gachaRecords: store.gachaRecords,
            plans: store.plans
        )
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            NavigationStack {
                HStack(spacing: 0) {
                    SidebarView(selection: $store.selectedSection)
                        .frame(minWidth: SidebarView.width, idealWidth: SidebarView.width, maxWidth: SidebarView.width, alignment: .leading)
                        .layoutPriority(10)

                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.45))
                        .frame(width: 1)

                    VStack(spacing: 0) {
                        HStack {
                            Spacer(minLength: 12)

                            ContentTopBar(
                                searchText: $store.searchText,
                                refresh: refreshCurrentSection,
                                openDataSource: {
                                    store.selectedSection = .settings
                                }
                            )
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(.ultraThinMaterial)
                        .softSeparator()

                        detailView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.clear)
        }
        .background {
            WindowGlassConfigurator()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshCurrentSection() {
        Task {
            if store.selectedSection == .gachaLog {
                await store.reloadLocalGachaRecords()
            } else {
                await store.load()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if trimmedSearchText.isEmpty {
            sectionView
        } else {
            GlobalSearchView(
                query: trimmedSearchText,
                results: globalSearchResults
            ) { result in
                store.selectedSection = result.section
                store.searchText = ""
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch store.selectedSection {
        case .overview:
            OverviewView(store: store)
        case .database:
            DatabaseView(store: store)
        case .gachaLog:
            GachaLogView(store: store)
        case .planner:
            PlannerView(store: store)
        case .account:
            AccountView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}

private struct ContentTopBar: View {
    @Binding var searchText: String
    let refresh: () -> Void
    let openDataSource: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button(action: refresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 34)
                }
                .delayedTooltip("按当前页面刷新相关数据。祈愿记录页会重新读取本机记录，其他页面会重新加载本机缓存、资料库、养成计划和账号状态。")

                Button(action: openDataSource) {
                    Label("数据源", systemImage: "externaldrive.badge.icloud")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 34)
                }
                .delayedTooltip("打开设置中的数据源管理，用于开启自动更新或导入离线资料包。")
            }
            .buttonStyle(.plain)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .glassPanel(cornerRadius: 22)

            FloatingSearchField(text: $searchText)
        }
    }
}

private struct FloatingSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 360, height: 44)
        .glassPanel(cornerRadius: 22)
    }
}
