import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var mapBrowser = OfficialMapBrowser()
    @State private var mapFloatingWindow = MapFloatingWindowController()
    @State private var cloudBrowser = CloudGameBrowser()
    @State private var hasOpenedCloudGame = false
    private var trimmedSearchText: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var globalSearchResults: [GlobalSearchResult] {
        GlobalSearchIndex.results(
            matching: store.searchText,
            metadata: store.metadata,
            gachaRecords: store.activeGachaRecords,
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
                                refresh: refreshRemoteData
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
        .onChange(of: store.accountStatus.accountID) { _, _ in
            mapBrowser.invalidateSession(ifAccountChangedTo: store.accountStatus.accountID)
            cloudBrowser.invalidateSession(ifAccountChangedTo: store.accountStatus.accountID)
        }
        .onChange(of: store.selectedSection) { _, section in
            if section == .cloudGame && !hasOpenedCloudGame {
                hasOpenedCloudGame = true
                Task { await cloudBrowser.open(session: (try? store.mapWebSessionContext()) ?? .guest) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshRemoteData() {
        Task {
            await store.manuallyRefreshRemoteData()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
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
            if hasOpenedCloudGame {
                CloudGameView(browser: cloudBrowser) {
                    Task { await cloudBrowser.open(session: (try? store.mapWebSessionContext()) ?? .guest) }
                }
                .opacity(store.selectedSection == .cloudGame && trimmedSearchText.isEmpty ? 1 : 0)
                .allowsHitTesting(store.selectedSection == .cloudGame && trimmedSearchText.isEmpty)
                .accessibilityHidden(store.selectedSection != .cloudGame || !trimmedSearchText.isEmpty)
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
        case .map:
            OfficialMapView(store: store, browser: mapBrowser, floatingWindow: mapFloatingWindow)
        case .cloudGame:
            Color.clear
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

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button(action: refresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 34)
                }
                .delayedTooltip("立即检查并更新资料库、当前卡池和公告。")
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
