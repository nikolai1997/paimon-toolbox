import CryptoKit
import XCTest
@testable import PaimonToolbox

@MainActor
final class RemoteDataPackageImporterTests: XCTestCase {
    override func tearDown() {
        MetadataRefreshCapturingURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testImportsValidMetadataPackageIntoCache() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let metadata = makeMetadata(version: "remote-2026.06.24")
        let packageURL = try makePackage(in: directory, metadata: metadata)
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        let imported = try await service.importMetadataPackage(from: packageURL)

        XCTAssertEqual(imported, metadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: DataGenerationStore.activeURL(for: cacheURL).path()))
        let cached = try await service.loadMetadata()
        XCTAssertEqual(cached, metadata)
    }

    func testRejectsUnsupportedManifestSchemaVersion() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "unsupported-schema"),
            schemaVersion: 2
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        await assertImportRejected(packageURL, by: service)
    }

    func testRejectsManifestMissingRequiredPublicFile() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "missing-latest"),
            transformManifestFiles: { files in
                files.filter { $0.kind != .latest }
            }
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        await assertImportRejected(packageURL, by: service)
    }

    func testRejectsDuplicateManifestKind() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "duplicate-kind"),
            transformManifestFiles: { files in
                files.map { file in
                    guard file.kind == .weapons else { return file }
                    return RemoteDataFile(path: file.path, sha256: file.sha256, kind: .characters)
                }
            }
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        await assertImportRejected(packageURL, by: service)
    }

    func testRejectsDuplicateManifestPath() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "duplicate-path"),
            transformManifestFiles: { files in
                let characters = files.first { $0.kind == .characters }!
                return files.map { file in
                    guard file.kind == .weapons else { return file }
                    return RemoteDataFile(path: characters.path, sha256: characters.sha256, kind: file.kind)
                }
            }
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        await assertImportRejected(packageURL, by: service)
    }

    func testRejectsEmptyOrMalformedManifestHashes() async throws {
        for invalidHash in ["", "xyz", String(repeating: "g", count: 64), String(repeating: "0", count: 63)] {
            let directory = try makeTemporaryDirectory()
            let cacheURL = directory.appending(path: "metadata-cache.json")
            let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
            let packageURL = try makePackage(
                in: directory,
                metadata: makeMetadata(version: "invalid-hash"),
                transformManifestFiles: { files in
                    files.map { file in
                        guard file.kind == .latest else { return file }
                        return RemoteDataFile(path: file.path, sha256: invalidHash, kind: file.kind)
                    }
                }
            )
            let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

            await assertImportRejected(packageURL, by: service)
        }
    }

    func testRejectsNonCanonicalMetadataPathOffline() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "nested-metadata"),
            metadataPath: "nested/metadata.json"
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        await assertImportRejected(packageURL, by: service)
    }

    func testRejectsNonCanonicalMetadataPathOnline() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let metadata = makeMetadata(version: "nested-metadata")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(metadata)
        let publicFiles = defaultPublicFiles()
        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "nested/metadata.json", sha256: sha256Hex(metadataData), kind: .metadata)
            ] + publicFiles.map { file in
                RemoteDataFile(path: file.path, sha256: sha256Hex(file.data), kind: file.kind)
            }
        )
        installRemoteResponses(metadataData: metadataData, publicFiles: publicFiles, manifest: manifest)
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        do {
            _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)
            XCTFail("Expected non-canonical online metadata path to be rejected")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: DataGenerationStore.activeURL(for: cacheURL).path()))
        }
    }

    func testLoadMetadataMigratesLegacyCacheWhenPrimaryIsMissing() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let legacyURL = directory.appending(path: "legacy-metadata.json")
        let metadata = makeMetadata(version: "legacy-2026.06.27")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: legacyURL, options: .atomic)
        let service = BundledMetadataService(metadataCacheURL: cacheURL, metadataFallbackURLs: [legacyURL])

        let loaded = try await service.loadMetadata()

        XCTAssertEqual(loaded, metadata)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path()))
    }

    func testLoadMetadataQuarantinesCorruptPrimaryAndUsesValidFallback() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let fallbackURL = directory.appending(path: "metadata-fallback.json")
        try Data("not-json".utf8).write(to: cacheURL)

        let metadata = makeMetadata(version: "fallback-2026.07.10")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: fallbackURL, options: .atomic)
        let service = BundledMetadataService(metadataCacheURL: cacheURL, metadataFallbackURLs: [fallbackURL])

        let loaded = try await service.loadMetadata()
        let reloaded = try await service.loadMetadata()

        XCTAssertEqual(loaded, metadata)
        XCTAssertEqual(reloaded, metadata)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path())
        XCTAssertTrue(siblings.contains { $0.hasPrefix("metadata-cache.json.corrupt-") })
    }

    func testGenerationPublishKeepsPreviousDataWhenInterruptedBeforePointerSwap() throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let oldMetadata = Data(#"{"version":"old"}"#.utf8)
        let newMetadata = Data(#"{"version":"new"}"#.utf8)
        let oldEvents = Data(#"[{"name":"old"}]"#.utf8)
        let newEvents = Data(#"[{"name":"new"}]"#.utf8)

        try DataGenerationStore.publish(
            metadataData: oldMetadata,
            publicFiles: ["gacha-events.json": oldEvents],
            metadataDestination: metadataURL,
            publicDestination: publicURL
        )

        XCTAssertThrowsError(
            try DataGenerationStore.publish(
                metadataData: newMetadata,
                publicFiles: ["gacha-events.json": newEvents],
                metadataDestination: metadataURL,
                publicDestination: publicURL,
                beforePointerSwap: { throw CocoaError(.fileWriteUnknown) }
            )
        )

        XCTAssertEqual(try Data(contentsOf: DataGenerationStore.activeURL(for: metadataURL)), oldMetadata)
        XCTAssertEqual(
            try Data(contentsOf: DataGenerationStore.activeURL(for: publicURL).appending(path: "gacha-events.json")),
            oldEvents
        )
        XCTAssertEqual(try generationDirectories(in: directory).count, 1)
    }

    func testPublishRetainsOnlyCurrentAndPreviousGeneration() throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicURL = directory.appending(path: "public-data", directoryHint: .isDirectory)

        for version in 1...4 {
            try DataGenerationStore.publish(
                metadataData: Data("metadata-\(version)".utf8),
                publicFiles: ["gacha-events.json": Data("events-\(version)".utf8)],
                metadataDestination: metadataURL,
                publicDestination: publicURL
            )
        }

        let generations = try generationDirectories(in: directory)
        XCTAssertEqual(generations.count, 2)
        XCTAssertEqual(try Data(contentsOf: DataGenerationStore.activeURL(for: metadataURL)), Data("metadata-4".utf8))
        XCTAssertTrue(
            try generations.contains { generation in
                try Data(contentsOf: generation.appending(path: "metadata-cache.json")) == Data("metadata-3".utf8)
            }
        )
    }

    func testQuarantineDirectoriesAreBounded() throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicURL = directory.appending(path: "public-data", directoryHint: .isDirectory)

        for version in 1...5 {
            try DataGenerationStore.publish(
                metadataData: Data("metadata-\(version)".utf8),
                publicFiles: [:],
                metadataDestination: metadataURL,
                publicDestination: publicURL
            )
            XCTAssertTrue(try DataGenerationStore.quarantineActiveGeneration(for: metadataURL))
        }

        XCTAssertLessThanOrEqual(try quarantineDirectories(in: directory).count, 2)
    }

    func testCorruptCurrentGenerationRollsBackToPreviousGenerationAsAWhole() async throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let previousMetadata = makeMetadata(version: "previous")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let previousMetadataData = try encoder.encode(previousMetadata)
        let previousEvents = Data("[]".utf8)
        try DataGenerationStore.publish(
            metadataData: previousMetadataData,
            publicFiles: ["gacha-events.json": previousEvents],
            metadataDestination: metadataURL,
            publicDestination: publicURL
        )
        try DataGenerationStore.publish(
            metadataData: Data("not-json".utf8),
            publicFiles: ["gacha-events.json": Data(#"[{"name":"new"}]"#.utf8)],
            metadataDestination: metadataURL,
            publicDestination: publicURL
        )
        let service = BundledMetadataService(
            metadataCacheURL: metadataURL,
            metadataFallbackURLs: [],
            publicDataCacheDirectory: publicURL
        )

        let loaded = try await service.loadMetadata()

        XCTAssertEqual(loaded, previousMetadata)
        XCTAssertEqual(
            try Data(contentsOf: DataGenerationStore.activeURL(for: publicURL).appending(path: "gacha-events.json")),
            previousEvents
        )
    }

    func testCorruptActiveGenerationFallsBackAsAWhole() async throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let fallbackURL = directory.appending(path: "metadata-fallback.json")
        let publicURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let oldPublicData = Data(#"[{"name":"old"}]"#.utf8)
        try FileManager.default.createDirectory(at: publicURL, withIntermediateDirectories: true)
        try oldPublicData.write(to: publicURL.appending(path: "gacha-events.json"))

        let metadata = makeMetadata(version: "fallback")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: fallbackURL, options: .atomic)
        try DataGenerationStore.publish(
            metadataData: Data("not-json".utf8),
            publicFiles: ["gacha-events.json": Data(#"[{"name":"new"}]"#.utf8)],
            metadataDestination: metadataURL,
            publicDestination: publicURL
        )
        let service = BundledMetadataService(
            metadataCacheURL: metadataURL,
            metadataFallbackURLs: [fallbackURL],
            publicDataCacheDirectory: publicURL
        )

        let loaded = try await service.loadMetadata()

        XCTAssertEqual(loaded, metadata)
        XCTAssertEqual(DataGenerationStore.activeURL(for: publicURL), publicURL)
        XCTAssertEqual(try Data(contentsOf: publicURL.appending(path: "gacha-events.json")), oldPublicData)
    }

    func testImportRollsBackMetadataWhenPublicDataCommitFails() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let invalidPublicDataDirectory = directory.appending(path: "public-data")
        let oldMetadata = makeMetadata(version: "old")
        let newMetadata = makeMetadata(version: "new")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(oldMetadata).write(to: cacheURL, options: .atomic)
        try Data("blocking file".utf8).write(to: invalidPublicDataDirectory)
        let packageURL = try makePackage(
            in: directory,
            metadata: newMetadata,
            extraFiles: [
                PackageExtraFile(path: "characters.json", kind: .characters, data: Data("[]".utf8))
            ]
        )
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: invalidPublicDataDirectory
        )

        do {
            _ = try await service.importMetadataPackage(from: packageURL)
            XCTFail("Expected the public data commit to fail")
        } catch {
            let cachedData = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            XCTAssertEqual(try decoder.decode(MetadataBundle.self, from: cachedData), oldMetadata)
        }
    }

    func testImportsPublicDataFilesIntoOverviewCache() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let gachaEventsData = """
        [
          {
            "banner": null,
            "from": "2026-06-05T18:00:00+08:00",
            "name": "霜锋夜白",
            "to": "2026-06-30T14:59:00+08:00",
            "type": 301,
            "upOrangeList": [10000123],
            "upPurpleList": [],
            "version": "6.6"
          }
        ]
        """.data(using: .utf8)!
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "remote-2026.06.24"),
            extraFiles: [
                PackageExtraFile(path: "gacha-events.json", kind: .gachaEvents, data: gachaEventsData)
            ]
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL, publicDataCacheDirectory: publicDataCache)

        _ = try await service.importMetadataPackage(from: packageURL)

        let cachedEventsURL = DataGenerationStore.activeURL(for: publicDataCache).appending(path: "gacha-events.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedEventsURL.path()))
        XCTAssertEqual(try Data(contentsOf: cachedEventsURL), gachaEventsData)
    }

    func testRefreshMetadataCachesSiblingPublicDataFilesFromManifest() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let metadata = makeMetadata(version: "remote-2026.06.24")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        let gachaEventsData = """
        [
          {
            "banner": null,
            "from": "2026-06-05T18:00:00+08:00",
            "name": "远程新卡池",
            "to": "2026-06-30T14:59:00+08:00",
            "type": 301,
            "upOrangeList": [10000123],
            "upPurpleList": [],
            "version": "6.6"
          }
        ]
        """.data(using: .utf8)!
        let publicFiles = mergedPublicFiles(overrides: [
            PackageExtraFile(path: "gacha-events.json", kind: .gachaEvents, data: gachaEventsData)
        ])
        let manifest = makeManifest(metadataData: metadataData, publicFiles: publicFiles)
        installRemoteResponses(metadataData: metadataData, publicFiles: publicFiles, manifest: manifest)
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        let refreshed = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(refreshed, metadata)
        XCTAssertEqual(
            try Data(contentsOf: DataGenerationStore.activeURL(for: publicDataCache).appending(path: "gacha-events.json")),
            gachaEventsData
        )
    }

    func testRefreshMetadataReplacesExistingSiblingPublicDataFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: publicDataCache, withIntermediateDirectories: true)
        try #"{"old":true}"#.data(using: .utf8)!.write(to: publicDataCache.appending(path: "characters.json"))

        let metadata = makeMetadata(version: "remote-2026.07.01")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        let charactersData = #"{"old":false}"#.data(using: .utf8)!
        let publicFiles = mergedPublicFiles(overrides: [
            PackageExtraFile(path: "characters.json", kind: .characters, data: charactersData)
        ])
        let manifest = makeManifest(metadataData: metadataData, publicFiles: publicFiles)
        installRemoteResponses(metadataData: metadataData, publicFiles: publicFiles, manifest: manifest)
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(
            try Data(contentsOf: DataGenerationStore.activeURL(for: publicDataCache).appending(path: "characters.json")),
            charactersData
        )
    }

    func testRefreshMetadataReplacesDanglingPublicDataFileLinks() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: publicDataCache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: publicDataCache.appending(path: "characters.json"),
            withDestinationURL: directory.appending(path: "missing-characters.json")
        )

        let metadata = makeMetadata(version: "remote-2026.07.01")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        let charactersData = #"{"characters":[]}"#.data(using: .utf8)!
        let publicFiles = mergedPublicFiles(overrides: [
            PackageExtraFile(path: "characters.json", kind: .characters, data: charactersData)
        ])
        let manifest = makeManifest(metadataData: metadataData, publicFiles: publicFiles)
        installRemoteResponses(metadataData: metadataData, publicFiles: publicFiles, manifest: manifest)
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(
            try Data(contentsOf: DataGenerationStore.activeURL(for: publicDataCache).appending(path: "characters.json")),
            charactersData
        )
    }

    func testRefreshMetadataDoesNotPartiallyOverwritePublicDataWhenLaterFileFails() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let publicDataCache = directory.appending(path: "public-data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: publicDataCache, withIntermediateDirectories: true)

        let cachedGachaEventsData = #"{"cached":true}"#.data(using: .utf8)!
        let freshGachaEventsData = #"{"cached":false}"#.data(using: .utf8)!
        let invalidConfigData = #"{"baseURL":"https://example.com"}"#.data(using: .utf8)!
        try cachedGachaEventsData.write(to: publicDataCache.appending(path: "gacha-events.json"), options: .atomic)

        let metadata = makeMetadata(version: "remote-2026.06.24")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        let publicFiles = mergedPublicFiles(overrides: [
            PackageExtraFile(path: "gacha-events.json", kind: .gachaEvents, data: freshGachaEventsData),
            PackageExtraFile(path: "config.json", kind: .config, data: invalidConfigData)
        ])
        let manifest = makeManifest(
            metadataData: metadataData,
            publicFiles: publicFiles,
            hashOverrides: [.config: String(repeating: "0", count: 64)]
        )
        installRemoteResponses(metadataData: metadataData, publicFiles: publicFiles, manifest: manifest)
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        do {
            _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)
            XCTFail("Expected refresh to fail when a manifest file hash does not match")
        } catch let error as MetadataPackageImportError {
            XCTAssertEqual(error, .hashMismatch("config.json"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: publicDataCache.appending(path: "gacha-events.json")), cachedGachaEventsData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: publicDataCache.appending(path: "config.json").path()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path()))
    }

    func testRejectsPackageWhenManifestHashDoesNotMatch() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "remote-2026.06.24"),
            metadataHashOverride: String(repeating: "0", count: 64)
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL)

        do {
            _ = try await service.importMetadataPackage(from: packageURL)
            XCTFail("Expected invalid package error")
        } catch let error as MetadataPackageImportError {
            XCTAssertEqual(error, .hashMismatch("metadata.json"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path()))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsPackageWithManifestTimestampFarInTheFuture() async throws {
        let directory = try makeTemporaryDirectory()
        let cacheURL = directory.appending(path: "metadata-cache.json")
        let packageURL = try makePackage(
            in: directory,
            metadata: makeMetadata(version: "future"),
            generatedAt: Date().addingTimeInterval(7 * 24 * 60 * 60)
        )
        let service = BundledMetadataService(metadataCacheURL: cacheURL)

        do {
            _ = try await service.importMetadataPackage(from: packageURL)
            XCTFail("Expected future manifest rejection")
        } catch let error as MetadataPackageImportError {
            XCTAssertEqual(error, .futureTimestamp)
        }
    }

    private func makeMetadata(version: String) -> MetadataBundle {
        MetadataBundle(
            version: version,
            updatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            characters: [
                GameCharacter(
                    id: 10000002,
                    name: "神里绫华",
                    element: "冰",
                    weaponType: "单手剑",
                    rarity: 5,
                    region: "稻妻",
                    materials: ["绯樱绣球", "恒常机关之心"]
                )
            ],
            weapons: [
                Weapon(
                    id: 11502,
                    name: "雾切之回光",
                    type: "单手剑",
                    rarity: 5,
                    stat: "暴击伤害",
                    materials: ["远海夷地的金枝"]
                )
            ],
            materials: [
                MaterialItem(
                    id: 2001,
                    name: "绯樱绣球",
                    category: "区域特产",
                    source: "稻妻野外采集"
                )
            ]
        )
    }

    private func makePackage(
        in directory: URL,
        metadata: MetadataBundle,
        metadataHashOverride: String? = nil,
        generatedAt: Date = Date(timeIntervalSince1970: 1_782_700_800),
        schemaVersion: Int = 1,
        metadataPath: String = "metadata.json",
        extraFiles: [PackageExtraFile] = [],
        transformManifestFiles: (([RemoteDataFile]) -> [RemoteDataFile])? = nil
    ) throws -> URL {
        let packageRoot = directory.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let metadataData = try encoder.encode(metadata)
        let metadataURL = packageRoot.appending(path: metadataPath)
        try FileManager.default.createDirectory(
            at: metadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try metadataData.write(to: metadataURL)

        let publicFiles = mergedPublicFiles(overrides: extraFiles)
        for extraFile in publicFiles {
            try extraFile.data.write(to: packageRoot.appending(path: extraFile.path))
        }

        let files = [
            RemoteDataFile(
                path: metadataPath,
                sha256: metadataHashOverride ?? sha256Hex(metadataData),
                kind: .metadata
            )
        ] + publicFiles.map { extraFile in
            RemoteDataFile(path: extraFile.path, sha256: sha256Hex(extraFile.data), kind: extraFile.kind)
        }
        let manifest = RemoteDataManifest(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            files: transformManifestFiles?(files) ?? files
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: packageRoot.appending(path: "manifest.json"))

        let zipURL = directory.appending(path: "data-pack.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--zlibCompressionLevel",
            "9",
            packageRoot.path(),
            zipURL.path()
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zipURL
    }

    private func assertImportRejected(
        _ packageURL: URL,
        by service: BundledMetadataService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await service.importMetadataPackage(from: packageURL)
            XCTFail("Expected invalid manifest to be rejected", file: file, line: line)
        } catch {
            // Rejection is the contract; individual error cases remain an implementation detail.
        }
    }

    private func mergedPublicFiles(overrides: [PackageExtraFile]) -> [PackageExtraFile] {
        var filesByKind = Dictionary(uniqueKeysWithValues: defaultPublicFiles().map { ($0.kind, $0) })
        for file in overrides {
            filesByKind[file.kind] = file
        }
        return requiredPublicKinds.compactMap { filesByKind[$0] }
    }

    private func defaultPublicFiles() -> [PackageExtraFile] {
        [
            PackageExtraFile(path: "characters.json", kind: .characters, data: Data("[]".utf8)),
            PackageExtraFile(path: "weapons.json", kind: .weapons, data: Data("[]".utf8)),
            PackageExtraFile(path: "materials.json", kind: .materials, data: Data("[]".utf8)),
            PackageExtraFile(path: "gacha-events.json", kind: .gachaEvents, data: Data("[]".utf8)),
            PackageExtraFile(path: "config.json", kind: .config, data: Data("{}".utf8)),
            PackageExtraFile(
                path: "announcements.json",
                kind: .announcements,
                data: Data(#"{"schemaVersion":1,"updatedAt":"2026-07-10T00:00:00Z","items":[]}"#.utf8)
            ),
            PackageExtraFile(
                path: "latest.json",
                kind: .latest,
                data: Data(#"{"schemaVersion":1,"dataVersion":"test","updatedAt":"2026-07-10T00:00:00Z","notes":"","required":false}"#.utf8)
            )
        ]
    }

    private var requiredPublicKinds: [RemoteDataFileKind] {
        [.characters, .weapons, .materials, .gachaEvents, .config, .announcements, .latest]
    }

    private func installRemoteResponses(
        metadataData: Data,
        publicFiles: [PackageExtraFile],
        manifest: RemoteDataManifest
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try! encoder.encode(manifest)
        let dataByName = Dictionary(uniqueKeysWithValues: publicFiles.map { ($0.path, $0.data) })
        MetadataRefreshCapturingURLProtocol.requestHandler = { request in
            let data: Data
            switch request.url?.lastPathComponent {
            case "metadata.json": data = metadataData
            case "manifest.json": data = manifestData
            case let name?:
                guard let publicData = dataByName[name] else {
                    return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
                }
                data = publicData
            case nil:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
    }

    private func makeManifest(
        metadataData: Data,
        publicFiles: [PackageExtraFile],
        hashOverrides: [RemoteDataFileKind: String] = [:]
    ) -> RemoteDataManifest {
        RemoteDataManifest(
            schemaVersion: RemoteDataManifest.currentSchemaVersion,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "metadata.json", sha256: sha256Hex(metadataData), kind: .metadata)
            ] + publicFiles.map { file in
                RemoteDataFile(
                    path: file.path,
                    sha256: hashOverrides[file.kind] ?? sha256Hex(file.data),
                    kind: file.kind
                )
            }
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func generationDirectories(in directory: URL) throws -> [URL] {
        let generationsRoot = directory.appending(path: ".paimon-data-generations", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: generationsRoot.path()) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: generationsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func quarantineDirectories(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { $0.lastPathComponent.hasPrefix(".paimon-corrupt-generation-") }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func capturingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetadataRefreshCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct PackageExtraFile {
    var path: String
    var kind: RemoteDataFileKind
    var data: Data
}

private final class MetadataRefreshCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
