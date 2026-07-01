import Foundation
import CryptoKit

@MainActor
protocol MetadataServicing {
    func loadMetadata() async throws -> MetadataBundle
    func refreshMetadata(from url: URL) async throws -> MetadataBundle
    func importMetadataPackage(from url: URL) async throws -> MetadataBundle
}

struct BundledMetadataService: MetadataServicing {
    private let metadataCacheURL: URL?
    private let metadataFallbackURLs: [URL]
    private let publicDataCacheDirectory: URL?
    private let urlSession: URLSession

    init(
        metadataCacheURL: URL? = nil,
        metadataFallbackURLs: [URL]? = nil,
        publicDataCacheDirectory: URL? = nil,
        urlSession: URLSession = .shared
    ) {
        self.metadataCacheURL = metadataCacheURL
        let fallbackURLs = metadataFallbackURLs ?? ((try? [AppPaths.legacyMetadataCacheURL]) ?? [])
        self.metadataFallbackURLs = fallbackURLs.filter { fallbackURL in
            guard let metadataCacheURL else {
                return true
            }
            return fallbackURL.standardizedFileURL.path() != metadataCacheURL.standardizedFileURL.path()
        }
        self.publicDataCacheDirectory = publicDataCacheDirectory
        self.urlSession = urlSession
    }

    func loadMetadata() async throws -> MetadataBundle {
        let cacheURL = try metadataCacheURL ?? AppPaths.metadataCacheURL
        if FileManager.default.fileExists(atPath: cacheURL.path()) {
            return try await decodeMetadataFile(at: cacheURL)
        }

        for fallbackURL in metadataFallbackURLs where FileManager.default.fileExists(atPath: fallbackURL.path()) {
            guard let metadata = try? await decodeMetadataFile(at: fallbackURL) else {
                continue
            }
            try migrateMetadataCache(from: fallbackURL, to: cacheURL)
            return metadata
        }

        guard let url = Bundle.module.url(forResource: "metadata.sample", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try await decodeMetadataFile(at: url)
    }

    func refreshMetadata(from url: URL) async throws -> MetadataBundle {
        let data = try await downloadData(from: url)
        let metadata = try await decodeMetadataData(data)
        try await refreshPublicDataFiles(relativeTo: url, metadataData: data)
        try data.write(to: try cacheURL(), options: .atomic)
        return metadata
    }

    func importMetadataPackage(from url: URL) async throws -> MetadataBundle {
        let extractionRoot = FileManager.default.temporaryDirectory
            .appending(path: "genshin-data-pack-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: extractionRoot)
        }

        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        try extractZip(at: url, to: extractionRoot)

        let packageRoot = try findPackageRoot(in: extractionRoot)
        let manifestData = try Data(contentsOf: packageRoot.appending(path: "manifest.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RemoteDataManifest.self, from: manifestData)

        for file in manifest.files {
            try validate(file: file, in: packageRoot)
        }

        guard let metadataFile = manifest.files.first(where: { $0.kind == .metadata }) else {
            throw MetadataPackageImportError.missingFile("metadata.json")
        }

        let metadataURL = packageRoot.appending(path: metadataFile.path)
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try await decodeMetadataData(metadataData)
        try metadataData.write(to: try cacheURL(), options: .atomic)
        try cachePublicDataFiles(from: packageRoot, manifest: manifest)
        return metadata
    }

    private func decodeMetadataFile(at url: URL) async throws -> MetadataBundle {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return try Self.decodeMetadata(from: data)
        }.value
    }

    private func decodeMetadataData(_ data: Data) async throws -> MetadataBundle {
        try await Task.detached(priority: .userInitiated) {
            try Self.decodeMetadata(from: data)
        }.value
    }

    nonisolated private static func decodeMetadata(from data: Data) throws -> MetadataBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MetadataBundle.self, from: data)
    }

    private func cacheURL() throws -> URL {
        try metadataCacheURL ?? AppPaths.metadataCacheURL
    }

    private func publicDataCacheURL() throws -> URL {
        try publicDataCacheDirectory ?? AppPaths.publicDataDirectory
    }

    private func migrateMetadataCache(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try copyReplacingItem(at: sourceURL, to: destinationURL)
    }

    private func cachePublicDataFiles(from packageRoot: URL, manifest: RemoteDataManifest) throws {
        let destination = try publicDataCacheURL()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for file in manifest.files where file.kind != .metadata {
            guard !file.path.contains("/") else {
                continue
            }
            let sourceURL = packageRoot.appending(path: file.path)
            let destinationURL = destination.appending(path: file.path)
            try copyReplacingItem(at: sourceURL, to: destinationURL)
        }
    }

    private func refreshPublicDataFiles(relativeTo metadataURL: URL, metadataData: Data) async throws {
        let baseURL = metadataURL.deletingLastPathComponent()
        let manifestURL = baseURL.appending(path: "manifest.json")
        let manifestData = try await downloadData(from: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RemoteDataManifest.self, from: manifestData)

        if let metadataFile = manifest.files.first(where: { $0.kind == .metadata }) {
            guard sha256Hex(metadataData).caseInsensitiveCompare(metadataFile.sha256) == .orderedSame else {
                throw MetadataPackageImportError.hashMismatch(metadataFile.path)
            }
        }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "paimon-public-data-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        for file in manifest.files where file.kind != .metadata {
            try validateFlatPath(file.path)
            let dataURL = baseURL.appending(path: file.path)
            let data = try await downloadData(from: dataURL)
            guard sha256Hex(data).caseInsensitiveCompare(file.sha256) == .orderedSame else {
                throw MetadataPackageImportError.hashMismatch(file.path)
            }
            let stagingURL = stagingDirectory.appending(path: file.path)
            try data.write(to: stagingURL, options: .atomic)
        }

        try commitPublicDataFiles(from: stagingDirectory, manifest: manifest)
    }

    private func commitPublicDataFiles(from stagingDirectory: URL, manifest: RemoteDataManifest) throws {
        let destination = try publicDataCacheURL()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for file in manifest.files where file.kind != .metadata {
            try validateFlatPath(file.path)
            let sourceURL = stagingDirectory.appending(path: file.path)
            let destinationURL = destination.appending(path: file.path)
            try copyReplacingItem(at: sourceURL, to: destinationURL)
        }
    }

    private func copyReplacingItem(at sourceURL: URL, to destinationURL: URL) throws {
        do {
            try FileManager.default.removeItem(at: destinationURL)
        } catch {
            guard isMissingFileError(error) else {
                throw error
            }
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == POSIXErrorCode.ENOENT.rawValue
        }
        return false
    }

    private func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await urlSession.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw MetadataRefreshError.badStatus(httpResponse.statusCode)
        }
        return data
    }

    private func validateFlatPath(_ path: String) throws {
        guard !path.hasPrefix("/"),
              !path.contains("/"),
              !path.split(separator: "/").contains("..") else {
            throw MetadataPackageImportError.unsafePath(path)
        }
    }

    private func extractZip(at zipURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            zipURL.path(),
            destinationURL.path()
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MetadataPackageImportError.invalidArchive
        }
    }

    private func findPackageRoot(in extractionRoot: URL) throws -> URL {
        let rootManifest = extractionRoot.appending(path: "manifest.json")
        if FileManager.default.fileExists(atPath: rootManifest.path()) {
            return extractionRoot
        }

        guard let enumerator = FileManager.default.enumerator(
            at: extractionRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MetadataPackageImportError.missingFile("manifest.json")
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "manifest.json" {
            return fileURL.deletingLastPathComponent()
        }

        throw MetadataPackageImportError.missingFile("manifest.json")
    }

    private func validate(file: RemoteDataFile, in packageRoot: URL) throws {
        guard !file.path.hasPrefix("/"),
              !file.path.split(separator: "/").contains("..") else {
            throw MetadataPackageImportError.unsafePath(file.path)
        }

        let fileURL = packageRoot.appending(path: file.path)
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            throw MetadataPackageImportError.missingFile(file.path)
        }

        let data = try Data(contentsOf: fileURL)
        guard sha256Hex(data).caseInsensitiveCompare(file.sha256) == .orderedSame else {
            throw MetadataPackageImportError.hashMismatch(file.path)
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum MetadataRefreshError: Error, LocalizedError {
    case badStatus(Int)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let status): "静态资源请求失败，HTTP \(status)"
        case .invalidURL: "静态资源地址无效"
        }
    }
}

enum MetadataPackageImportError: Error, Equatable, LocalizedError {
    case invalidArchive
    case missingFile(String)
    case hashMismatch(String)
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "数据包无法解压，请确认选择的是 data-pack.zip"
        case .missingFile(let path):
            "数据包缺少文件：\(path)"
        case .hashMismatch(let path):
            "数据包校验失败：\(path)"
        case .unsafePath(let path):
            "数据包包含不安全路径：\(path)"
        }
    }
}
