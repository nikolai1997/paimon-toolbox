import XCTest

final class AppearanceSettingsTests: XCTestCase {
    func testSettingsExposeThemePickerOptions() throws {
        let settingsSource = try Self.source("Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("主题"))
        XCTAssertTrue(settingsSource.contains("Picker(\"主题\""))
        XCTAssertTrue(settingsSource.contains("跟随系统"))
        XCTAssertTrue(settingsSource.contains("白天"))
        XCTAssertTrue(settingsSource.contains("黑夜"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(AppAppearanceSettings.themeKey)"))
    }

    func testAppAppliesPreferredColorSchemeToMainAndSettingsWindows() throws {
        let appSource = try Self.source("App/PaimonToolboxApp.swift")
        let appearanceSource = try Self.source("Support/AppAppearanceSettings.swift")

        XCTAssertTrue(appearanceSource.contains("enum AppTheme"))
        XCTAssertTrue(appearanceSource.contains("var preferredColorScheme: ColorScheme?"))
        XCTAssertTrue(appearanceSource.contains("case system"))
        XCTAssertTrue(appearanceSource.contains("case light"))
        XCTAssertTrue(appearanceSource.contains("case dark"))
        XCTAssertEqual(appSource.components(separatedBy: ".preferredColorScheme(appTheme.preferredColorScheme)").count - 1, 2)
    }

    func testAppStartsAutomaticSignInMonitorAfterInitialLoad() throws {
        let appSource = try Self.source("App/PaimonToolboxApp.swift")

        let loadRange = try XCTUnwrap(appSource.range(of: "await store.load()"))
        let monitorRange = try XCTUnwrap(appSource.range(of: "await store.startAutomaticSignInMonitor()"))
        XCTAssertLessThan(loadRange.lowerBound, monitorRange.lowerBound)
    }

    func testAutomaticSignInUsesCalendarMorningSchedule() throws {
        let settingsSource = try Self.source("Support/AutoSignInSettings.swift")
        let storeSource = try Self.source("Stores/AppStore.swift")
        let settingsViewSource = try Self.source("Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("scheduledAttemptPrefix"))
        XCTAssertTrue(settingsSource.contains("morningWindowStartHour"))
        XCTAssertTrue(settingsSource.contains("morningWindowEndHour"))
        XCTAssertTrue(settingsSource.contains("idleWakeInterval"))
        XCTAssertTrue(storeSource.contains("nextAutomaticSignInMonitorDate"))
        XCTAssertTrue(storeSource.contains("scheduledDailySignInDate"))
        XCTAssertTrue(storeSource.contains("scheduleAutomaticSignInWake"))
        XCTAssertTrue(storeSource.contains("cancelAutomaticSignInWake"))
        XCTAssertTrue(settingsViewSource.contains(".onChange(of: isAutoSignInEnabled)"))
        XCTAssertFalse(storeSource.contains("intervalNanoseconds"))
    }

    func testSettingsExposeAutomaticSignInWindowPicker() throws {
        let settingsSource = try Self.source("Support/AutoSignInSettings.swift")
        let settingsViewSource = try Self.source("Views/SettingsView.swift")

        XCTAssertTrue(settingsSource.contains("enum AutoSignInWindow"))
        XCTAssertTrue(settingsSource.contains("windowKey"))
        XCTAssertTrue(settingsSource.contains("08:00-12:00"))
        XCTAssertTrue(settingsSource.contains("12:00-16:00"))
        XCTAssertTrue(settingsSource.contains("18:00-22:00"))
        XCTAssertTrue(settingsViewSource.contains("@AppStorage(AutoSignInSettings.windowKey)"))
        XCTAssertTrue(settingsViewSource.contains("Picker(\"自动签到时间\""))
        XCTAssertTrue(settingsViewSource.contains(".onChange(of: autoSignInWindowRawValue)"))
    }

    func testMobileUserAgentMatchesSnapHutaoAndroidBridgeEnvironment() throws {
        let source = try Self.source("Services/HoYoRequestSigner.swift")

        XCTAssertTrue(source.contains("Linux; Android 15"))
        XCTAssertTrue(source.contains("Mobile miHoYoBBS/2.95.1"))
        XCTAssertFalse(source.contains("iPhone; CPU iPhone OS 17_0"))
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
