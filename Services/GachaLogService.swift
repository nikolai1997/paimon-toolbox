import Foundation

@MainActor
protocol GachaLogServicing {
    func loadRecords() async throws -> [GachaRecord]
    func importRecords(from url: URL, into existing: [GachaRecord]) async throws -> [GachaRecord]
    func exportRecords(_ records: [GachaRecord], to url: URL) async throws
    func replaceRecords(_ records: [GachaRecord]) async throws
    func summary(for records: [GachaRecord]) -> GachaSummary
}

struct LocalGachaLogService: GachaLogServicing {
    private static let recordsMirrorKey = "gacha.records.nativeMirror"
    private let recordsURL: URL?
    private let legacyRecordURLs: [URL]
    private let userDefaults: UserDefaults

    init(recordsURL: URL? = nil, legacyRecordURLs: [URL]? = nil, userDefaults: UserDefaults = .standard) {
        self.recordsURL = recordsURL
        self.legacyRecordURLs = legacyRecordURLs ?? Self.defaultLegacyRecordURLs()
        self.userDefaults = userDefaults
    }

    func loadRecords() async throws -> [GachaRecord] {
        let primaryURL = try recordsFileURL()
        var merged: [GachaRecord] = []
        var didReadAnyRecordsFile = false
        var didReadMigratableFile = false
        var firstDecodeError: Error?

        for url in candidateRecordURLs(primaryURL: primaryURL) where FileManager.default.fileExists(atPath: url.path()) {
            do {
                let data = try Data(contentsOf: url)
                let records = try GachaLogDocument.decodeRecords(from: data)
                merged = GachaLogDocument.mergedRecords(existing: merged, imported: records)
                didReadAnyRecordsFile = true
                if !Self.isSameFile(url, primaryURL) {
                    didReadMigratableFile = true
                }
            } catch {
                if firstDecodeError == nil {
                    firstDecodeError = error
                }
            }
        }

        if let mirrored = try loadMirroredRecords(), !mirrored.isEmpty {
            merged = GachaLogDocument.mergedRecords(existing: merged, imported: mirrored)
            didReadAnyRecordsFile = true
            didReadMigratableFile = true
        }

        if didReadAnyRecordsFile {
            if didReadMigratableFile {
                try? await replaceRecords(merged)
            }
            return merged.sorted { $0.time > $1.time }
        }

        if let firstDecodeError {
            throw firstDecodeError
        }
        return []
    }

    func importRecords(from url: URL, into existing: [GachaRecord]) async throws -> [GachaRecord] {
        let data = try Data(contentsOf: url)
        let imported = try GachaLogDocument.decodeRecords(from: data)
        let merged = GachaLogDocument.mergedRecords(existing: existing, imported: imported)
        try await replaceRecords(merged)
        return merged
    }

    func exportRecords(_ records: [GachaRecord], to url: URL) async throws {
        let data = try GachaLogDocument.encodeUIGFRecords(records)
        try data.write(to: url, options: .atomic)
    }

    func replaceRecords(_ records: [GachaRecord]) async throws {
        let data = try GachaLogDocument.encodeNativeRecords(records.sorted { $0.time > $1.time })
        userDefaults.set(data, forKey: Self.recordsMirrorKey)
        let url = try recordsFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func summary(for records: [GachaRecord]) -> GachaSummary {
        GachaSummary.make(from: records)
    }

    private func recordsFileURL() throws -> URL {
        try recordsURL ?? AppPaths.gachaRecordsURL
    }

    private func loadMirroredRecords() throws -> [GachaRecord]? {
        guard let data = userDefaults.data(forKey: Self.recordsMirrorKey) else {
            return nil
        }
        return try GachaLogDocument.decodeRecords(from: data)
    }

    private func candidateRecordURLs(primaryURL: URL) -> [URL] {
        var seen = Set<String>()
        return ([primaryURL] + legacyRecordURLs).filter { url in
            let key = url.standardizedFileURL.path()
            return seen.insert(key).inserted
        }
    }

    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path() == rhs.standardizedFileURL.path()
    }

    private static func defaultLegacyRecordURLs() -> [URL] {
        let homes = Self.possibleUserHomeDirectories()

        var urls: [URL] = []
        for home in homes {
            let appSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            let containers = home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Containers", isDirectory: true)

            urls.append(contentsOf: [
                appSupport
                    .appendingPathComponent("派蒙工具箱", isDirectory: true)
                    .appendingPathComponent("gacha-records.json"),
                appSupport
                    .appendingPathComponent("原神工具箱", isDirectory: true)
                    .appendingPathComponent("gacha-records.json"),
                appSupport
                    .appendingPathComponent("PaimonToolbox", isDirectory: true)
                    .appendingPathComponent("gacha-records.json"),
                appSupport
                    .appendingPathComponent("GenshinToolbox", isDirectory: true)
                    .appendingPathComponent("gacha-records.json"),
                appSupport
                    .appendingPathComponent("com.nikolai.paimon-toolbox", isDirectory: true)
                    .appendingPathComponent("gacha-records.json"),
                appSupport
                    .appendingPathComponent("com.nikolai.genshin-toolbox", isDirectory: true)
                    .appendingPathComponent("gacha-records.json")
            ])

            for containerName in [
                "com.nikolai.paimon-toolbox",
                "com.nikolai.genshin-toolbox",
                "PaimonToolbox",
                "GenshinToolbox",
                "原神工具箱",
                "派蒙工具箱"
            ] {
                let containerSupport = containers
                    .appendingPathComponent(containerName, isDirectory: true)
                    .appendingPathComponent("Data", isDirectory: true)
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)

                urls.append(
                    containerSupport
                        .appendingPathComponent("派蒙工具箱", isDirectory: true)
                        .appendingPathComponent("gacha-records.json")
                )
                urls.append(
                    containerSupport
                        .appendingPathComponent("原神工具箱", isDirectory: true)
                        .appendingPathComponent("gacha-records.json")
                )
                urls.append(
                    containerSupport
                        .appendingPathComponent("PaimonToolbox", isDirectory: true)
                        .appendingPathComponent("gacha-records.json")
                )
                urls.append(
                    containerSupport
                        .appendingPathComponent("GenshinToolbox", isDirectory: true)
                        .appendingPathComponent("gacha-records.json")
                )
            }
        }

        return urls
    }

    private static func possibleUserHomeDirectories() -> [URL] {
        var homes = [
            FileManager.default.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        ]

        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            homes.append(URL(fileURLWithPath: home, isDirectory: true))
        }

        let userName = NSUserName()
        if !userName.isEmpty {
            homes.append(URL(fileURLWithPath: "/Users/\(userName)", isDirectory: true))
        }

        var seen = Set<String>()
        return homes.filter { home in
            let key = home.standardizedFileURL.path()
            return seen.insert(key).inserted
        }
    }
}
