import XCTest

final class SidebarLayoutTests: XCTestCase {
    func testSidebarKeepsFixedWidthInContentLayout() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".frame(minWidth: SidebarView.width, idealWidth: SidebarView.width, maxWidth: SidebarView.width, alignment: .leading)"))
        XCTAssertTrue(source.contains(".layoutPriority(10)"))
        XCTAssertFalse(source.contains(".fixedSize(horizontal: true, vertical: false)"))
    }

    func testSidebarOwnsStableWidthConstant() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/SidebarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("static let width: CGFloat = 236"))
        XCTAssertTrue(source.contains("private static let horizontalPadding: CGFloat = 14"))
        XCTAssertTrue(source.contains(".padding(.horizontal, Self.horizontalPadding)"))
        XCTAssertTrue(source.contains(".frame(minWidth: Self.width, idealWidth: Self.width, maxWidth: Self.width, alignment: .leading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)"))
    }
}
