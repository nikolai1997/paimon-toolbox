import XCTest

final class GlassHoverGlowTests: XCTestCase {
    func testGlassPanelsTrackPointerForHoverGlow() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Support/GlassSurfaces.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("GlassHoverGlowModifier"))
        XCTAssertTrue(source.contains(".onContinuousHover"))
        XCTAssertTrue(source.contains(".glassHoverGlow(cornerRadius: cornerRadius)"))
    }
}
