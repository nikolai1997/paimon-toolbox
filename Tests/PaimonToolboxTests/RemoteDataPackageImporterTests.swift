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
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path()))
        let cached = try await service.loadMetadata()
        XCTAssertEqual(cached, metadata)
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

        let cachedEventsURL = publicDataCache.appending(path: "gacha-events.json")
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
        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "metadata.json", sha256: sha256Hex(metadataData), kind: .metadata),
                RemoteDataFile(path: "gacha-events.json", sha256: sha256Hex(gachaEventsData), kind: .gachaEvents)
            ]
        )
        let manifestData = try encoder.encode(manifest)
        MetadataRefreshCapturingURLProtocol.requestHandler = { request in
            switch request.url?.lastPathComponent {
            case "metadata.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, metadataData)
            case "manifest.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestData)
            case "gacha-events.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, gachaEventsData)
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        let refreshed = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(refreshed, metadata)
        XCTAssertEqual(try Data(contentsOf: publicDataCache.appending(path: "gacha-events.json")), gachaEventsData)
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
        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "metadata.json", sha256: sha256Hex(metadataData), kind: .metadata),
                RemoteDataFile(path: "characters.json", sha256: sha256Hex(charactersData), kind: .characters)
            ]
        )
        let manifestData = try encoder.encode(manifest)
        MetadataRefreshCapturingURLProtocol.requestHandler = { request in
            switch request.url?.lastPathComponent {
            case "metadata.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, metadataData)
            case "manifest.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestData)
            case "characters.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, charactersData)
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(try Data(contentsOf: publicDataCache.appending(path: "characters.json")), charactersData)
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
        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "metadata.json", sha256: sha256Hex(metadataData), kind: .metadata),
                RemoteDataFile(path: "characters.json", sha256: sha256Hex(charactersData), kind: .characters)
            ]
        )
        let manifestData = try encoder.encode(manifest)
        MetadataRefreshCapturingURLProtocol.requestHandler = { request in
            switch request.url?.lastPathComponent {
            case "metadata.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, metadataData)
            case "manifest.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestData)
            case "characters.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, charactersData)
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
        let service = BundledMetadataService(
            metadataCacheURL: cacheURL,
            publicDataCacheDirectory: publicDataCache,
            urlSession: Self.capturingSession()
        )

        _ = try await service.refreshMetadata(from: URL(string: "https://example.com/data/metadata.json")!)

        XCTAssertEqual(try Data(contentsOf: publicDataCache.appending(path: "characters.json")), charactersData)
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
        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(path: "metadata.json", sha256: sha256Hex(metadataData), kind: .metadata),
                RemoteDataFile(path: "gacha-events.json", sha256: sha256Hex(freshGachaEventsData), kind: .gachaEvents),
                RemoteDataFile(path: "config.json", sha256: String(repeating: "0", count: 64), kind: .config)
            ]
        )
        let manifestData = try encoder.encode(manifest)
        MetadataRefreshCapturingURLProtocol.requestHandler = { request in
            switch request.url?.lastPathComponent {
            case "metadata.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, metadataData)
            case "manifest.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestData)
            case "gacha-events.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, freshGachaEventsData)
            case "config.json":
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, invalidConfigData)
            default:
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
        }
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
        extraFiles: [PackageExtraFile] = []
    ) throws -> URL {
        let packageRoot = directory.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let metadataData = try encoder.encode(metadata)
        let metadataURL = packageRoot.appending(path: "metadata.json")
        try metadataData.write(to: metadataURL)

        for extraFile in extraFiles {
            try extraFile.data.write(to: packageRoot.appending(path: extraFile.path))
        }

        let manifest = RemoteDataManifest(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_782_700_800),
            files: [
                RemoteDataFile(
                    path: "metadata.json",
                    sha256: metadataHashOverride ?? sha256Hex(metadataData),
                    kind: .metadata
                )
            ] + extraFiles.map { extraFile in
                RemoteDataFile(path: extraFile.path, sha256: sha256Hex(extraFile.data), kind: extraFile.kind)
            }
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
