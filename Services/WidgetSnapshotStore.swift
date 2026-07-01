import Foundation

protocol WidgetSnapshotStoring {
    func load() throws -> WidgetSnapshot
    func save(_ snapshot: WidgetSnapshot) throws
}

struct LocalWidgetSnapshotStore: WidgetSnapshotStoring {
    static let appGroupIdentifier = "group.com.nikolai.paimon-toolbox"
    static let legacyAppGroupIdentifier = "group.com.nikolai.genshin-toolbox"
    static let widgetExtensionBundleIdentifier = "com.nikolai.paimon-toolbox.widgets"

    private let snapshotURL: URL
    private let fallbackSnapshotURLs: [URL]

    init() throws {
        let primaryURL = try Self.defaultSnapshotURL()
        if Self.isRunningInWidgetExtension {
            snapshotURL = primaryURL
            fallbackSnapshotURLs = []
            return
        }

        let appSupportURL = try Self.appSupportSnapshotURL()
        let legacyURL = try Self.legacyAppSupportSnapshotURL()
        let widgetContainerURL = try Self.widgetExtensionContainerSnapshotURL()
        snapshotURL = primaryURL
        fallbackSnapshotURLs = [appSupportURL, widgetContainerURL, legacyURL]
            .filter { $0 != primaryURL }
    }

    init(snapshotURL: URL, fallbackSnapshotURL: URL? = nil) {
        self.snapshotURL = snapshotURL
        self.fallbackSnapshotURLs = fallbackSnapshotURL.map { [$0] } ?? []
    }

    static func defaultSnapshotURL() throws -> URL {
        try appSupportSnapshotURL()
    }

    private static var isRunningInWidgetExtension: Bool {
        Bundle.main.bundleIdentifier == widgetExtensionBundleIdentifier
    }

    static func groupContainerSnapshotURL() throws -> URL {
        try groupContainerSnapshotURL(appGroupIdentifier: appGroupIdentifier)
    }

    static func legacyGenshinAppGroupSnapshotURL() throws -> URL {
        try groupContainerSnapshotURL(appGroupIdentifier: legacyAppGroupIdentifier)
    }

    private static func groupContainerSnapshotURL(appGroupIdentifier: String) throws -> URL {
        let libraryURL = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return libraryURL
            .appending(path: "Group Containers", directoryHint: .isDirectory)
            .appending(path: appGroupIdentifier, directoryHint: .isDirectory)
            .appending(path: "widget-snapshot.json")
    }

    static func widgetExtensionContainerSnapshotURL() throws -> URL {
        let libraryURL = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return libraryURL
            .appending(path: "Containers", directoryHint: .isDirectory)
            .appending(path: widgetExtensionBundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Data", directoryHint: .isDirectory)
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: AppPaths.appFolderName, directoryHint: .isDirectory)
            .appending(path: "widget-snapshot.json")
    }

    static func appSupportSnapshotURL() throws -> URL {
        return try AppPaths.appSupportDirectoryURL().appending(path: "widget-snapshot.json")
    }

    static func legacyAppSupportSnapshotURL() throws -> URL {
        return try AppPaths.legacyAppSupportDirectoryURL().appending(path: "widget-snapshot.json")
    }

    func load() throws -> WidgetSnapshot {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            if let snapshot = loadUsefulFallbackSnapshot() {
                try? save(snapshot, to: snapshotURL)
                return snapshot
            }
            return .empty
        }

        let snapshot = try load(from: snapshotURL)
        if snapshot.hasDisplayableContent {
            return snapshot
        }
        if let fallbackSnapshot = loadUsefulFallbackSnapshot() {
            try? save(fallbackSnapshot, to: snapshotURL)
            return fallbackSnapshot
        }
        return snapshot
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try save(snapshot, to: snapshotURL)
        for fallbackSnapshotURL in fallbackSnapshotURLs where fallbackSnapshotURL != snapshotURL {
            try? save(snapshot, to: fallbackSnapshotURL)
        }
    }

    private func loadUsefulFallbackSnapshot() -> WidgetSnapshot? {
        for fallbackSnapshotURL in fallbackSnapshotURLs where fallbackSnapshotURL != snapshotURL {
            guard FileManager.default.fileExists(atPath: fallbackSnapshotURL.path),
                  let snapshot = try? load(from: fallbackSnapshotURL),
                  snapshot.hasDisplayableContent
            else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private func load(from url: URL) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetSnapshot.self, from: Data(contentsOf: url))
    }

    private func save(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
