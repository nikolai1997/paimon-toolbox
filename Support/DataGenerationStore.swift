import Foundation

enum DataGenerationStore {
    private static let generationsDirectoryName = ".paimon-data-generations"
    private static let currentPointerName = ".paimon-current-generation"
    private static let previousPointerName = ".paimon-previous-generation"
    private static let quarantinePrefix = ".paimon-corrupt-generation-"
    private static let maximumQuarantineCount = 2

    static func activeURL(for legacyDestination: URL) -> URL {
        let root = legacyDestination.deletingLastPathComponent()
        let pointerURL = root.appending(path: currentPointerName)
        guard let generationID = generationID(at: pointerURL) else {
            return legacyDestination
        }
        let candidate = generationRoot(for: generationID, under: root)
            .appending(path: legacyDestination.lastPathComponent)
        return FileManager.default.fileExists(atPath: candidate.path()) ? candidate : legacyDestination
    }

    static func publish(
        metadataData: Data,
        publicFiles: [String: Data],
        metadataDestination: URL,
        publicDestination: URL,
        beforePointerSwap: () throws -> Void = {}
    ) throws {
        let metadataRoot = metadataDestination.deletingLastPathComponent().standardizedFileURL
        let publicRoot = publicDestination.deletingLastPathComponent().standardizedFileURL
        guard metadataRoot == publicRoot else {
            throw MetadataPackageImportError.invalidDestination(publicDestination.path())
        }

        let newGenerationID = UUID().uuidString.lowercased()
        let generationsRoot = metadataRoot.appending(path: generationsDirectoryName, directoryHint: .isDirectory)
        let newGenerationRoot = generationRoot(for: newGenerationID, under: metadataRoot)
        let generationMetadata = newGenerationRoot.appending(path: metadataDestination.lastPathComponent)
        let generationPublic = newGenerationRoot.appending(path: publicDestination.lastPathComponent, directoryHint: .isDirectory)
        let currentPointerURL = metadataRoot.appending(path: currentPointerName)
        let previousPointerURL = metadataRoot.appending(path: previousPointerName)
        let previousCurrentID = generationID(at: currentPointerURL).flatMap { candidate in
            FileManager.default.fileExists(atPath: generationRoot(for: candidate, under: metadataRoot).path())
                ? candidate
                : nil
        }

        try FileManager.default.createDirectory(at: generationPublic, withIntermediateDirectories: true)
        do {
            try metadataData.write(to: generationMetadata, options: .atomic)
            for (path, data) in publicFiles {
                guard isFlatPath(path) else {
                    throw MetadataPackageImportError.unsafePath(path)
                }
                try data.write(to: generationPublic.appending(path: path), options: .atomic)
            }
            try beforePointerSwap()

            if let previousCurrentID {
                try writePointer(previousCurrentID, to: previousPointerURL)
            } else {
                try removeIfPresent(previousPointerURL)
            }
            try writePointer(newGenerationID, to: currentPointerURL)
        } catch {
            try? FileManager.default.removeItem(at: newGenerationRoot)
            throw error
        }

        try? cleanupGenerations(in: generationsRoot, keeping: [newGenerationID, previousCurrentID].compactMap { $0 })
        try? cleanupQuarantines(in: metadataRoot)
    }

    static func quarantineActiveGeneration(for legacyDestination: URL) throws -> Bool {
        let root = legacyDestination.deletingLastPathComponent().standardizedFileURL
        let currentPointerURL = root.appending(path: currentPointerName)
        guard let currentID = generationID(at: currentPointerURL) else {
            return false
        }

        let currentRoot = generationRoot(for: currentID, under: root)
        let activeDestination = currentRoot.appending(path: legacyDestination.lastPathComponent)
        guard FileManager.default.fileExists(atPath: activeDestination.path()) else {
            return false
        }

        let previousPointerURL = root.appending(path: previousPointerName)
        let previousID = generationID(at: previousPointerURL).flatMap { candidate -> String? in
            guard candidate != currentID,
                  FileManager.default.fileExists(atPath: generationRoot(for: candidate, under: root).path()) else {
                return nil
            }
            return candidate
        }
        let quarantineURL = root.appending(
            path: "\(quarantinePrefix)\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )

        try FileManager.default.moveItem(at: currentRoot, to: quarantineURL)
        if let previousID {
            try writePointer(previousID, to: currentPointerURL)
        } else {
            try removeIfPresent(currentPointerURL)
        }
        try removeIfPresent(previousPointerURL)

        let generationsRoot = root.appending(path: generationsDirectoryName, directoryHint: .isDirectory)
        try? cleanupGenerations(in: generationsRoot, keeping: previousID.map { [$0] } ?? [])
        try? cleanupQuarantines(in: root)
        return true
    }

    private static func generationID(at pointerURL: URL) -> String? {
        guard let value = try? String(contentsOf: pointerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              isSafeGenerationID(value) else {
            return nil
        }
        return value
    }

    private static func generationRoot(for generationID: String, under root: URL) -> URL {
        root.appending(path: generationsDirectoryName, directoryHint: .isDirectory)
            .appending(path: generationID, directoryHint: .isDirectory)
    }

    private static func writePointer(_ generationID: String, to url: URL) throws {
        try Data("\(generationID)\n".utf8).write(to: url, options: .atomic)
    }

    private static func cleanupGenerations(in generationsRoot: URL, keeping generationIDs: [String]) throws {
        guard FileManager.default.fileExists(atPath: generationsRoot.path()) else {
            return
        }
        let retained = Set(generationIDs)
        for url in try FileManager.default.contentsOfDirectory(
            at: generationsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) where !retained.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func cleanupQuarantines(in root: URL) throws {
        let quarantines = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.lastPathComponent.hasPrefix(quarantinePrefix) }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        for quarantine in quarantines.dropFirst(maximumQuarantineCount) {
            try FileManager.default.removeItem(at: quarantine)
        }
    }

    private static func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let nsError = error as NSError
            guard (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.fileNoSuchFile.rawValue)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == POSIXErrorCode.ENOENT.rawValue) else {
                throw error
            }
        }
    }

    private static func isSafeGenerationID(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    }

    private static func isFlatPath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("/") && value != "." && value != ".."
    }
}
