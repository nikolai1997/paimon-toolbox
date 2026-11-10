import XCTest
@testable import PaimonToolbox

final class SidebarVisibilityTests: XCTestCase {
    func testVisibilityPersistsIndependentlyAndCanBeRestored() {
        var hidden = SidebarVisibility.setting(.map, visible: false, hidden: "")
        hidden = SidebarVisibility.setting(.planner, visible: false, hidden: hidden)
        XCTAssertFalse(SidebarVisibility.isVisible(.map, hidden: hidden))
        XCTAssertFalse(SidebarVisibility.isVisible(.planner, hidden: hidden))
        XCTAssertTrue(SidebarVisibility.isVisible(.overview, hidden: hidden))
        hidden = SidebarVisibility.setting(.map, visible: true, hidden: hidden)
        XCTAssertTrue(SidebarVisibility.isVisible(.map, hidden: hidden))
        XCTAssertFalse(SidebarVisibility.isVisible(.planner, hidden: hidden))
    }

    func testSettingsRemainsVisible() {
        XCTAssertTrue(SidebarVisibility.isVisible(.settings, hidden: "settings"))
        XCTAssertEqual(SidebarVisibility.setting(.settings, visible: false, hidden: ""), "")
    }
}
