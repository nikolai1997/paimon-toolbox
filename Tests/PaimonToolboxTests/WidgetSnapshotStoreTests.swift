import XCTest
@testable import PaimonToolbox

final class WidgetSnapshotStoreTests: XCTestCase {
    func testStoreSavesAndLoadsSnapshotWithDates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "widget-snapshot.json")
        let store = LocalWidgetSnapshotStore(snapshotURL: url)
        let generatedAt = Date(timeIntervalSince1970: 1_780_000_000.125)
        let lastFiveStarDate = Date(timeIntervalSince1970: 1_780_000_123.875)
        let snapshot = WidgetSnapshot(
            generatedAt: generatedAt,
            signIn: .signedOut,
            gacha: WidgetGachaSnapshot(
                totalPulls: 81,
                fiveStarCount: 1,
                fourStarCount: 9,
                pitySinceLastFiveStar: 0,
                lastFiveStarName: "刻晴",
                lastFiveStarDate: lastFiveStarDate,
                characterPulls: 81,
                weaponPulls: 0,
                standardPulls: 0
            ),
            planner: .empty
        )

        try store.save(snapshot)

        let loaded = try store.load()
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.generatedAt, generatedAt)
        XCTAssertEqual(loaded.gacha.lastFiveStarDate, lastFiveStarDate)
    }

    func testMissingSnapshotReturnsEmptySnapshot() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "missing-widget-snapshot.json")
        let store = LocalWidgetSnapshotStore(snapshotURL: url)

        XCTAssertEqual(try store.load(), .empty)
    }

    func testEmptyPrimarySnapshotMigratesUsefulFallbackSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryURL = directory.appending(path: "primary-widget-snapshot.json")
        let fallbackURL = directory.appending(path: "legacy-widget-snapshot.json")
        let usefulFallback = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_780_000_200),
            signIn: WidgetSignInSnapshot(
                isSignedIn: true,
                nickname: "我爱老登",
                uid: "110209152",
                isTodaySigned: true,
                totalSignDay: 26,
                statusText: "已签到",
                actionTitle: "查看账号",
                message: nil
            ),
            gacha: WidgetGachaSnapshot(
                totalPulls: 938,
                fiveStarCount: 17,
                fourStarCount: 118,
                pitySinceLastFiveStar: 3,
                lastFiveStarName: "梦见月瑞希",
                lastFiveStarDate: nil,
                characterPulls: 761,
                weaponPulls: 0,
                standardPulls: 177
            ),
            planner: .empty
        )
        let emptyStore = LocalWidgetSnapshotStore(snapshotURL: primaryURL)
        let fallbackStore = LocalWidgetSnapshotStore(snapshotURL: fallbackURL)
        try emptyStore.save(.empty)
        try fallbackStore.save(usefulFallback)

        let migratingStore = LocalWidgetSnapshotStore(snapshotURL: primaryURL, fallbackSnapshotURL: fallbackURL)
        let loaded = try migratingStore.load()

        XCTAssertEqual(loaded.signIn.nickname, "我爱老登")
        XCTAssertEqual(loaded.gacha.totalPulls, 938)
        XCTAssertEqual(try emptyStore.load().signIn.nickname, "我爱老登")
    }

    func testExplicitSnapshotURLOverridesSharedContainerLookup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "custom-widget-snapshot.json")
        let store = LocalWidgetSnapshotStore(snapshotURL: url)

        try store.save(.empty)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDefaultSnapshotFallbackUsesNonCreatingAppSupportURL() throws {
        let appPathsSource = try Self.source("Support/AppPaths.swift")
        let storeSource = try Self.source("Services/WidgetSnapshotStore.swift")

        XCTAssertTrue(appPathsSource.contains("static func appSupportDirectoryURL() throws -> URL"))
        XCTAssertTrue(appPathsSource.contains("create: false"))
        XCTAssertTrue(storeSource.contains("AppPaths.appSupportDirectoryURL().appending(path: \"widget-snapshot.json\")"))
        XCTAssertFalse(storeSource.contains("return try AppPaths.widgetSnapshotURL"))
    }

    func testDefaultStoreMirrorsSnapshotsToWidgetExtensionContainer() throws {
        let storeSource = try Self.source("Services/WidgetSnapshotStore.swift")

        XCTAssertTrue(storeSource.contains("fallbackSnapshotURLs"))
        XCTAssertTrue(storeSource.contains("legacyAppSupportSnapshotURL"))
        XCTAssertTrue(storeSource.contains("widgetExtensionContainerSnapshotURL"))
        XCTAssertTrue(storeSource.contains("AppPaths.legacyAppSupportDirectoryURL().appending(path: \"widget-snapshot.json\")"))
        XCTAssertTrue(storeSource.contains("try? save(snapshot, to: fallbackSnapshotURL)"))
        XCTAssertFalse(storeSource.contains("containerURL(forSecurityApplicationGroupIdentifier"))
    }

    func testWidgetExtensionUsesOwnSandboxSnapshotToAvoidAppGroupLookup() throws {
        let storeSource = try Self.source("Services/WidgetSnapshotStore.swift")

        XCTAssertTrue(storeSource.contains("widgetExtensionBundleIdentifier"))
        XCTAssertTrue(storeSource.contains("Bundle.main.bundleIdentifier == widgetExtensionBundleIdentifier"))
        XCTAssertTrue(storeSource.contains("if Self.isRunningInWidgetExtension"))
        XCTAssertTrue(storeSource.contains("fallbackSnapshotURLs = []"))
        XCTAssertTrue(storeSource.contains("widgetExtensionContainerSnapshotURL"))
        XCTAssertTrue(storeSource.contains(".appending(path: \"Containers\", directoryHint: .isDirectory)"))
        XCTAssertTrue(storeSource.contains(".appending(path: widgetExtensionBundleIdentifier, directoryHint: .isDirectory)"))
    }

    private static func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
