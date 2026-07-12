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
        let legacyCacheURL = try metadataCacheURL ?? AppPaths.metadataCacheURL
        var cacheURL = DataGenerationStore.activeURL(for: legacyCacheURL)
        while FileManager.default.fileExists(atPath: cacheURL.path()) {
            do {
                return try await decodeMetadataFile(at: cacheURL)
            } catch {
                if try DataGenerationStore.quarantineActiveGeneration(for: legacyCacheURL) {
                    cacheURL = DataGenerationStore.activeURL(for: legacyCacheURL)
                } else {
                    try quarantineCorruptCache(at: cacheURL)
                    break
                }
            }
        }

        for fallbackURL in metadataFallbackURLs where FileManager.default.fileExists(atPath: fallbackURL.path()) {
            guard let metadata = try? await decodeMetadataFile(at: fallbackURL) else {
                continue
            }
            try migrateMetadataCache(from: fallbackURL, to: legacyCacheURL)
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
        try validate(manifest: manifest)

        for file in manifest.files {
            try validate(file: file, in: packageRoot)
        }

        guard let metadataFile = manifest.files.first(where: { $0.kind == .metadata }) else {
            throw MetadataPackageImportError.missingFile("metadata.json")
        }

        let metadataURL = packageRoot.appending(path: metadataFile.path)
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try await decodeMetadataData(metadataData)
        try commitDataGeneration(metadataData: metadataData, publicSourceDirectory: packageRoot, manifest: manifest)
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

    private func refreshPublicDataFiles(relativeTo metadataURL: URL, metadataData: Data) async throws {
        let baseURL = metadataURL.deletingLastPathComponent()
        let manifestURL = baseURL.appending(path: "manifest.json")
        let manifestData = try await downloadData(from: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(RemoteDataManifest.self, from: manifestData)
        try validate(manifest: manifest)

        guard let metadataFile = manifest.files.first(where: { $0.kind == .metadata }) else {
            throw MetadataPackageImportError.missingKind(.metadata)
        }
        guard sha256Hex(metadataData).caseInsensitiveCompare(metadataFile.sha256) == .orderedSame else {
            throw MetadataPackageImportError.hashMismatch(metadataFile.path)
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

        try commitDataGeneration(metadataData: metadataData, publicSourceDirectory: stagingDirectory, manifest: manifest)
    }

    private func commitDataGeneration(
        metadataData: Data,
        publicSourceDirectory: URL,
        manifest: RemoteDataManifest
    ) throws {
        let metadataDestination = try cacheURL()
        let publicDestination = try publicDataCacheURL()
        if FileManager.default.fileExists(atPath: publicDestination.path()) {
            let values = try publicDestination.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw MetadataPackageImportError.invalidDestination(publicDestination.path())
            }
        }

        var publicFiles: [String: Data] = [:]
        for file in manifest.files where file.kind != .metadata {
            try validateFlatPath(file.path)
            let sourceURL = publicSourceDirectory.appending(path: file.path)
            let data = try Data(contentsOf: sourceURL)
            try validateJSONData(data, path: file.path)
            publicFiles[file.path] = data
        }
        try DataGenerationStore.publish(
            metadataData: metadataData,
            publicFiles: publicFiles,
            metadataDestination: metadataDestination,
            publicDestination: publicDestination
        )
    }

    private func validateJSONData(_ data: Data, path: String) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MetadataPackageImportError.invalidJSON(path)
        }
    }

    private func quarantineCorruptCache(at url: URL) throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        var quarantineURL = url.appendingPathExtension("corrupt-\(timestamp)")
        if FileManager.default.fileExists(atPath: quarantineURL.path()) {
            quarantineURL = url.appendingPathExtension("corrupt-\(timestamp)-\(UUID().uuidString)")
        }
        try FileManager.default.moveItem(at: url, to: quarantineURL)
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            guard isMissingFileError(error) else { throw error }
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

    private func validate(manifest: RemoteDataManifest, now: Date = Date()) throws {
        guard manifest.schemaVersion == RemoteDataManifest.currentSchemaVersion else {
            throw MetadataPackageImportError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard manifest.generatedAt <= now.addingTimeInterval(24 * 60 * 60) else {
            throw MetadataPackageImportError.futureTimestamp
        }

        var kinds: Set<RemoteDataFileKind> = []
        var paths: Set<String> = []
        for file in manifest.files {
            guard kinds.insert(file.kind).inserted else {
                throw MetadataPackageImportError.duplicateKind(file.kind)
            }
            guard paths.insert(file.path).inserted else {
                throw MetadataPackageImportError.duplicatePath(file.path)
            }
            guard file.path == file.kind.canonicalPath else {
                throw MetadataPackageImportError.unexpectedPath(kind: file.kind, path: file.path)
            }
            guard isValidSHA256(file.sha256) else {
                throw MetadataPackageImportError.invalidHash(file.path)
            }
        }

        guard kinds.contains(.metadata) else {
            throw MetadataPackageImportError.missingKind(.metadata)
        }
        for kind in RemoteDataFileKind.requiredPublicKinds where !kinds.contains(kind) {
            throw MetadataPackageImportError.missingKind(kind)
        }
    }

    private func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
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
    case invalidJSON(String)
    case invalidDestination(String)
    case futureTimestamp
    case unsupportedSchemaVersion(Int)
    case missingKind(RemoteDataFileKind)
    case duplicateKind(RemoteDataFileKind)
    case duplicatePath(String)
    case unexpectedPath(kind: RemoteDataFileKind, path: String)
    case invalidHash(String)

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
        case .invalidJSON(let path):
            "数据包 JSON 格式无效：\(path)"
        case .invalidDestination(let path):
            "数据缓存目录无效：\(path)"
        case .futureTimestamp:
            "数据包生成时间异常，已拒绝导入"
        case .unsupportedSchemaVersion(let version):
            "数据包版本不受支持：\(version)"
        case .missingKind(let kind):
            "数据包缺少必需文件：\(kind.canonicalPath)"
        case .duplicateKind(let kind):
            "数据包文件类型重复：\(kind.rawValue)"
        case .duplicatePath(let path):
            "数据包文件路径重复：\(path)"
        case .unexpectedPath(let kind, let path):
            "数据包文件路径无效：\(kind.rawValue) 应为 \(kind.canonicalPath)，实际为 \(path)"
        case .invalidHash(let path):
            "数据包 SHA-256 格式无效：\(path)"
        }
    }
}
