import XCTest

final class ToolbarLayoutTests: XCTestCase {
    func testGlobalToolbarActionsUseContentTopBarOutsideSystemToolbar() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ContentTopBar("))
        XCTAssertFalse(source.contains(".toolbar {"))
        XCTAssertFalse(source.contains(".searchable("))
        XCTAssertFalse(source.contains(".navigationTitle("))
        XCTAssertFalse(source.contains(".ignoresSafeArea(.container, edges: .top)"))
        XCTAssertTrue(source.contains(".frame(height: 58)"))
    }

    func testMainWindowUsesSingleWindowSceneForWidgetDeepLinks() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/PaimonToolboxApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Window(\"派蒙工具箱\", id: \"main\")"))
        XCTAssertFalse(source.contains("WindowGroup(\"派蒙工具箱\")"))
        XCTAssertTrue(source.contains(".windowStyle(.hiddenTitleBar)"))
        XCTAssertTrue(source.contains(".onOpenURL"))
    }

    func testWindowUsesTransparentBackgroundToAvoidOpaqueResizeStrip() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Support/WindowGlass.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("window.backgroundColor = .clear"))
        XCTAssertTrue(source.contains("window.isOpaque = false"))
    }
}
