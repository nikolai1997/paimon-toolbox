import XCTest

final class GlassHoverGlowTests: XCTestCase {
    func testGlassPanelsRespectDynamicLightingPreferenceAndThrottlePointerUpdates() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Support/GlassSurfaces.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("GlassHoverGlowModifier"))
        XCTAssertTrue(source.contains("@AppStorage(AppAppearanceSettings.dynamicLightingEnabledKey)"))
        XCTAssertTrue(source.contains("if isDynamicLightingEnabled"))
        XCTAssertTrue(source.contains(".onContinuousHover"))
        XCTAssertTrue(source.contains("abs(location.x - hoverLocation.x) >= 18"))
        XCTAssertTrue(source.contains(".glassHoverGlow(cornerRadius: cornerRadius)"))
    }
}
