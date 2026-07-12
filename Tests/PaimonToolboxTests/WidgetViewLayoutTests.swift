import XCTest

final class WidgetViewLayoutTests: XCTestCase {
    func testWidgetViewsUseSystemManagedWidgetChrome() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(source.contains("SmallSignInWidgetView"))
        XCTAssertTrue(source.contains("MediumGachaWidgetView"))
        XCTAssertTrue(source.contains("LargeToolboxWidgetView"))
        XCTAssertTrue(source.contains("import WidgetKit"))
        XCTAssertTrue(source.contains("widgetAccentedSymbol"))
        XCTAssertTrue(source.contains("widgetAccentedRenderingMode(.fullColor)"))
        XCTAssertTrue(source.contains("SmallWidgetSystemPlaceholderView"))
        XCTAssertTrue(source.contains("MediumWidgetSystemPlaceholderView"))
        XCTAssertTrue(source.contains("LargeWidgetSystemPlaceholderView"))
        XCTAssertTrue(source.contains("待签到"))
        XCTAssertTrue(source.contains("祈愿记录"))
        XCTAssertTrue(source.contains("今日养成"))
        XCTAssertTrue(source.contains("去签到"))
        XCTAssertTrue(source.contains("打开工具箱"))
        XCTAssertFalse(source.contains(".glassEffect("))
        XCTAssertFalse(source.contains(".regularMaterial"))
        XCTAssertFalse(source.contains("LinearGradient"))
        XCTAssertFalse(source.contains(".widgetGlass"))
    }

    func testWidgetTextUsesSystemForegroundToAvoidAccentedModeOverprint() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertFalse(source.contains("WidgetAdaptiveForeground"))
        XCTAssertFalse(source.contains("widgetAccentedPrimary"))
        XCTAssertFalse(source.contains("widgetAccentedSecondary"))
        XCTAssertTrue(source.contains("widgetStablePrimary"))
        XCTAssertTrue(source.contains("widgetStableSecondary"))
        XCTAssertTrue(source.contains(".widgetAccentable(false)"))
        XCTAssertTrue(source.contains("WidgetStableForeground"))
        XCTAssertTrue(source.contains("Color.white.opacity(fallbackOpacity)"))
        XCTAssertTrue(source.contains("fallbackOpacity: 0.96"))
        XCTAssertTrue(source.contains("fallbackOpacity: Double = 0.82"))
        XCTAssertTrue(source.contains("fallbackOpacity: 0.78"))
    }

    func testDesktopWidgetViewsAvoidSystemLabelInDesktopRenderingModes() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertNil(
            source.range(of: #"(?m)^\s*Label\("#, options: .regularExpression),
            "Desktop widgets should compose Image and Text explicitly so accented rendering does not drop label titles or symbols."
        )
        XCTAssertTrue(source.contains("Image(systemName:"))
        XCTAssertTrue(source.contains("Text("))
    }

    func testDesktopWidgetCriticalContentUsesReadableForegroundInsteadOfSemanticTint() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertFalse(source.contains("WidgetReadableForeground"))
        XCTAssertFalse(source.contains("widgetReadablePrimary"))
        XCTAssertTrue(source.contains("WidgetStableForeground"))
        XCTAssertTrue(source.contains("widgetStablePrimary"))
        XCTAssertFalse(source.contains(".widgetSemanticForeground(tint"))
        XCTAssertFalse(source.contains("Text(\"打开工具箱\")\n                        .font(.headline.weight(.regular))\n                        .lineLimit(1)\n                        .minimumScaleFactor(0.72)\n                        .widgetSemanticForeground(.blue)"))
        XCTAssertFalse(source.contains("Text(\"今日养成\")\n                        .font(.headline.weight(.regular))\n                        .lineLimit(1)\n                        .minimumScaleFactor(0.78)\n                        .widgetSemanticForeground(.blue)"))
    }

    func testCompactWidgetHeaderTextUsesNativeForegroundToAvoidGlassOverprint() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(source.contains("widgetNativePrimary"))
        XCTAssertTrue(source.contains("widgetNativeSecondary"))
        XCTAssertFalse(source.contains("WidgetSolidForeground"))
        XCTAssertFalse(source.contains("widgetSolidPrimary"))
        XCTAssertFalse(source.contains("widgetSolidSecondary"))
        XCTAssertFalse(source.contains("Color(white: white)"))
        XCTAssertTrue(source.contains(".font(.system(size: 13, weight: .regular, design: .default))"))
        XCTAssertTrue(source.contains(".font(.system(size: 12, weight: .regular, design: .default))"))
        XCTAssertTrue(source.contains(".font(.system(size: 11, weight: .regular, design: .default))"))
        XCTAssertFalse(source.contains("Text(\"祈愿记录\")\n                            .font(.headline.weight(.regular))"))
        XCTAssertFalse(source.contains("Text(signIn.uid.map { \"UID \\($0)\" } ?? signIn.message ?? \"登录后显示签到状态\")\n                    .font(.caption)"))
        XCTAssertFalse(source.contains("Text(gacha.totalPulls == 0 ? \"同步记录后显示五星与垫数\" : \"最近五星\")\n                        .font(.caption)"))
    }

    func testMediumAndLargeWidgetsUseFullColorAccents() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(source.contains("WidgetFullColorTintBackground"))
        XCTAssertTrue(source.contains("widgetTintBackground(.blue"))
        XCTAssertTrue(source.contains("tint: .blue"))
        XCTAssertTrue(source.contains("tint: .orange"))
        XCTAssertTrue(source.contains("tint: .purple"))
        XCTAssertTrue(source.contains("tint: snapshot.signIn.isTodaySigned ? .green : .orange"))
        XCTAssertTrue(source.contains(".widgetTintBackground(tint"))
        XCTAssertTrue(source.contains("fullColorOpacity: Double = 0.24"))
        XCTAssertTrue(source.contains("tint.opacity(fullColorOpacity)"))
        XCTAssertTrue(source.contains("Color.black.opacity(0.12)"))
        XCTAssertTrue(source.contains("renderingMode == .fullColor"))
    }

    func testLargeWidgetFocusUsesStrongerTintWithoutChangingNonFocusFallback() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(source.contains("fullColorOpacity: Double = 0.24"))
        XCTAssertTrue(source.contains("tint.opacity(fullColorOpacity)"))
        XCTAssertTrue(source.contains("Color.black.opacity(0.12)"))
        XCTAssertEqual(source.components(separatedBy: "fullColorOpacity: 0.42").count - 1, 3)
        XCTAssertTrue(source.contains(".widgetTintBackground(tint, cornerRadius: 18, fullColorOpacity: 0.42)"))
        XCTAssertTrue(source.contains(".widgetTintBackground(.blue, cornerRadius: 18, fullColorOpacity: 0.42)"))
    }

    func testWidgetConfigurationAllowsSystemPlaceholderRenderingModes() throws {
        let source = try Self.source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertTrue(source.contains(".containerBackgroundRemovable(false)"))
        XCTAssertFalse(source.contains(".unredacted()\n            .widgetAccentable(false)"))
        XCTAssertTrue(source.contains(".privacySensitive(false)"))
        XCTAssertTrue(source.contains(".unredacted()"))
        XCTAssertTrue(source.contains(".redacted(reason: [])"))
        XCTAssertTrue(source.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(source.contains("ToolboxWidgetBackground"))
        XCTAssertTrue(source.contains("#available(macOS 26.0, *)"))
        XCTAssertTrue(source.contains(".glassEffect(.regular"))
        XCTAssertTrue(source.contains(".rect(cornerRadius: 32"))
        XCTAssertTrue(source.contains(".fill(.regularMaterial)"))
        XCTAssertFalse(source.contains("startPoint: .topLeading,\n                    endPoint: .bottomTrailing"))
        XCTAssertFalse(source.contains("Color.white.opacity(0.34)"))
        XCTAssertFalse(source.contains("Color.mint.opacity(0.06)"))
        XCTAssertEqual(source.components(separatedBy: ".glassEffect(").count - 1, 1)
    }

    func testWidgetViewsAvoidNestedCustomGlassComponents() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertFalse(source.contains(".widgetGlassBadge"))
        XCTAssertFalse(source.contains(".widgetGlassAction"))
        XCTAssertFalse(source.contains(".widgetInnerGlass"))
        XCTAssertFalse(source.contains(".background(.ultraThinMaterial, in: RoundedRectangle"))
        XCTAssertFalse(source.contains(".background(Color.accentColor.opacity(0.18), in: RoundedRectangle"))
    }

    func testSettingsExposesWidgetPreview() throws {
        let source = try Self.source("Views/SettingsView.swift")

        XCTAssertTrue(source.contains("桌面小组件"))
        XCTAssertTrue(source.contains("WidgetPreviewPanel"))
    }

    func testWidgetPreviewPanelFitsNarrowSettingsWindow() throws {
        let source = try Self.source("Views/Widgets/WidgetPreviewPanel.swift")

        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("previewStack"))
        XCTAssertTrue(source.contains("WidgetPreviewTile"))
        XCTAssertTrue(source.contains("scaleEffect"))
        XCTAssertFalse(
            source.contains(".frame(width: 760)"),
            "The preview panel should not rely on a single wide fixed-width preview."
        )
    }

    func testWidgetPreviewPanelDoesNotDuplicateSettingsSectionTitle() throws {
        let source = try Self.source("Views/Widgets/WidgetPreviewPanel.swift")

        XCTAssertFalse(source.contains("Label(\"桌面小组件\""))
    }

    func testSettingsWidgetPreviewIsNotInteractive() throws {
        let previewSource = try Self.source("Views/Widgets/WidgetPreviewPanel.swift")
        let widgetSource = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(previewSource.contains("isInteractive: false"))
        XCTAssertTrue(widgetSource.contains("var isInteractive = true"))
    }

    func testDesktopWidgetViewsDoNotNestLinksInsideWidgetURL() throws {
        let viewSource = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")
        let extensionSource = try Self.source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertTrue(extensionSource.contains(".widgetURL(URL(string: \"paimontoolbox://widget/refresh\"))"))
        XCTAssertTrue(extensionSource.contains(".widgetURL(URL(string: \"paimontoolbox://gacha\"))"))
        XCTAssertTrue(extensionSource.contains(".widgetURL(URL(string: \"paimontoolbox://overview\"))"))
        XCTAssertFalse(viewSource.contains("Link(destination: URL(string: \"paimontoolbox://account/signin\")"))
        XCTAssertFalse(viewSource.contains("Link(destination: URL(string: \"paimontoolbox://gacha\")"))
        XCTAssertFalse(viewSource.contains("Link(destination: URL(string: \"paimontoolbox://overview\")"))
        XCTAssertFalse(viewSource.contains("Link(destination:"))
    }

    func testWidgetViewsDoNotPresentStaticRefreshTextAsAnInteractiveControl() throws {
        let viewSource = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")
        let extensionSource = try Self.source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertFalse(viewSource.contains("arrow.clockwise"))
        XCTAssertFalse(viewSource.contains("Text(\"刷新\")"))
        XCTAssertTrue(extensionSource.contains("paimontoolbox://widget/refresh"))
    }

    func testMediumWidgetUsesCompactHorizontalMetrics() throws {
        let source = try Self.source("Views/Widgets/ToolboxWidgetViews.swift")

        XCTAssertTrue(source.contains("HStack(spacing: 6)"))
        XCTAssertTrue(source.contains("CompactWidgetMetric"))
        XCTAssertFalse(source.contains("VStack(spacing: 10) {\n                WidgetMetricPill"))
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
