import SwiftUI
import WidgetKit

struct ToolboxWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isSystemPlaceholder: Bool
}

struct ToolboxWidgetProvider: TimelineProvider {
    private let snapshotStore: WidgetSnapshotStoring

    init(snapshotStore: WidgetSnapshotStoring? = nil) {
        if let snapshotStore {
            self.snapshotStore = snapshotStore
        } else {
            self.snapshotStore = (try? LocalWidgetSnapshotStore()) ?? EmptyWidgetSnapshotStore()
        }
    }

    func placeholder(in context: Context) -> ToolboxWidgetEntry {
        ToolboxWidgetEntry(date: Date(), snapshot: .empty, isSystemPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ToolboxWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ToolboxWidgetEntry>) -> Void) {
        let now = Date()
        let entry = entry(at: now)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func entry(at date: Date) -> ToolboxWidgetEntry {
        ToolboxWidgetEntry(
            date: date,
            snapshot: (try? snapshotStore.load()) ?? .empty,
            isSystemPlaceholder: false
        )
    }
}

struct EmptyWidgetSnapshotStore: WidgetSnapshotStoring {
    func load() throws -> WidgetSnapshot {
        .empty
    }

    func save(_ snapshot: WidgetSnapshot) throws {}
}

struct ToolboxWidgetEntryView: View {
    var entry: ToolboxWidgetProvider.Entry

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        widgetContent
            .unredacted()
            .redacted(reason: [])
            .privacySensitive(false)
            .containerBackground(for: .widget) {
                ToolboxWidgetBackground()
            }
    }

    @ViewBuilder
    private var widgetContent: some View {
        if entry.isSystemPlaceholder {
            switch widgetFamily {
            case .systemSmall:
                SmallWidgetSystemPlaceholderView()
            case .systemMedium:
                MediumWidgetSystemPlaceholderView()
            default:
                LargeWidgetSystemPlaceholderView()
            }
        } else {
            switch widgetFamily {
            case .systemSmall:
                SmallSignInWidgetView(snapshot: entry.snapshot)
                    .widgetURL(URL(string: "paimontoolbox://widget/refresh"))
            case .systemMedium:
                MediumGachaWidgetView(snapshot: entry.snapshot)
                    .widgetURL(URL(string: "paimontoolbox://gacha"))
            default:
                LargeToolboxWidgetView(snapshot: entry.snapshot)
                    .widgetURL(URL(string: "paimontoolbox://overview"))
            }
        }
    }
}

private struct ToolboxWidgetBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 32, style: .continuous))
        } else {
            Rectangle()
                .fill(.regularMaterial)
        }
    }
}

@main
struct PaimonToolboxWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaimonToolboxWidgets()
    }
}

struct PaimonToolboxWidgets: Widget {
    let kind = PaimonToolboxWidgetConfiguration.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ToolboxWidgetProvider()) { entry in
            ToolboxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("派蒙工具箱")
        .description("查看签到、祈愿记录和今日养成。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}
