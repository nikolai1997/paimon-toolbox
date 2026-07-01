import XCTest

final class OverviewViewLayoutTests: XCTestCase {
    func testOverviewUsesPaimonBrandingAndRichEmptyGachaState() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("派蒙工具箱"))
        XCTAssertTrue(source.contains("祈愿记录待同步"))
        XCTAssertTrue(source.contains("CurrentGachaEventsPanel"))
        XCTAssertFalse(source.contains("Text(\"本地优先工具箱\")"))
        XCTAssertFalse(source.contains("metric(\"祈愿记录\""))
    }

    func testOverviewDoesNotShowDataStatusPanel() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("DataStatusPanel"))
        XCTAssertFalse(source.contains("数据状态"))
    }
}
