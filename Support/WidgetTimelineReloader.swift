import WidgetKit

enum PaimonToolboxWidgetConfiguration {
    static let kind = "PaimonToolboxWidgets"
}

protocol WidgetTimelineReloading {
    func reloadTimelines(ofKind kind: String)
}

struct WidgetTimelineReloader: WidgetTimelineReloading {
    func reloadTimelines(ofKind kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
