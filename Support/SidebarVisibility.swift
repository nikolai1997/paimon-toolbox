import Foundation

enum SidebarVisibility {
    static let key = "sidebar.hiddenSections"

    static func isVisible(_ section: AppSection, hidden: String) -> Bool {
        section == .settings || !hidden.split(separator: ",").contains(Substring(section.rawValue))
    }

    static func setting(_ section: AppSection, visible: Bool, hidden: String) -> String {
        guard section != .settings else { return hidden }
        var values = Set(hidden.split(separator: ",").map(String.init))
        if visible {
            values.remove(section.rawValue)
        } else {
            values.insert(section.rawValue)
        }
        return values.sorted().joined(separator: ",")
    }
}
