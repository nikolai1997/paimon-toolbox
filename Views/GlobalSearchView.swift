import SwiftUI

struct GlobalSearchView: View {
    let query: String
    let results: [GlobalSearchResult]
    let openResult: (GlobalSearchResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if results.isEmpty {
                    ContentUnavailableView(
                        "没有找到结果",
                        systemImage: "magnifyingglass",
                        description: Text("可以搜索页面名称、按钮文字、设置说明、角色、武器、材料、祈愿记录和养成计划。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .glassPanel(cornerRadius: 18)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(results) { result in
                            Button {
                                openResult(result)
                            } label: {
                                resultRow(result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .glassPagePadding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("搜索 “\(query)”")
                .font(.largeTitle.bold())
                .lineLimit(2)
            Text("\(results.count) 个结果")
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(_ result: GlobalSearchResult) -> some View {
        HStack(spacing: 14) {
            Image(systemName: result.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(result.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(result.section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16)
    }
}
