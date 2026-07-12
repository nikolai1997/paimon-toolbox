import Foundation

@MainActor
protocol OverviewDataServicing {
    func loadOverviewData() async throws -> OverviewData
}

struct LocalOverviewDataService: OverviewDataServicing {
    var publicDataDirectory: URL?
    var fallbackPublicDataDirectories: [URL]?

    init(
        publicDataDirectory: URL? = nil,
        fallbackPublicDataDirectories: [URL]? = nil
    ) {
        self.publicDataDirectory = publicDataDirectory
        self.fallbackPublicDataDirectories = fallbackPublicDataDirectories
    }

    func loadOverviewData() async throws -> OverviewData {
        try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for source in Self.candidateSources(
                primaryDirectory: publicDataDirectory,
                fallbackDirectories: fallbackPublicDataDirectories
            ) {
                do {
                    return try Self.decodeOverviewData(from: source.root, decoder: decoder)
                } catch {
                    if let generationDestination = source.generationDestination {
                        _ = try DataGenerationStore.quarantineActiveGeneration(for: generationDestination)
                        var rollbackRoot = DataGenerationStore.activeURL(for: generationDestination)
                        while rollbackRoot.standardizedFileURL != generationDestination.standardizedFileURL {
                            do {
                                return try Self.decodeOverviewData(from: rollbackRoot, decoder: decoder)
                            } catch {
                                guard try DataGenerationStore.quarantineActiveGeneration(for: generationDestination) else {
                                    break
                                }
                                rollbackRoot = DataGenerationStore.activeURL(for: generationDestination)
                            }
                        }
                    }
                }
            }

            return .empty
        }.value
    }

    nonisolated private static func decodeOverviewData(from root: URL, decoder: JSONDecoder) throws -> OverviewData {
        let latest = try decode(
            RemoteLatestInfo.self,
            at: root.appending(path: RemoteDataFileKind.latest.canonicalPath),
            decoder: decoder
        )
        let gachaEvents = try decode(
            [GachaEventInfo].self,
            at: root.appending(path: RemoteDataFileKind.gachaEvents.canonicalPath),
            decoder: decoder
        )
        let announcementFeed = try? decode(
            AnnouncementFeed.self,
            at: root.appending(path: RemoteDataFileKind.announcements.canonicalPath),
            decoder: decoder
        )
        let announcements: [AnnouncementItem]
        if let announcementFeed, !announcementFeed.items.isEmpty {
            announcements = announcementFeed.items
        } else {
            announcements = synthesizedAnnouncements(from: gachaEvents)
        }

        return OverviewData(latest: latest, announcements: announcements, gachaEvents: gachaEvents)
    }

    nonisolated private static func decode<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        decoder: JSONDecoder
    ) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    nonisolated private static func candidateSources(
        primaryDirectory: URL?,
        fallbackDirectories: [URL]?
    ) -> [OverviewDataSource] {
        var sources: [OverviewDataSource] = []
        var seenRoots: Set<String> = []

        func appendSource(root: URL, generationDestination: URL? = nil) {
            let standardizedRoot = root.standardizedFileURL
            guard seenRoots.insert(standardizedRoot.path()).inserted else {
                return
            }
            sources.append(
                OverviewDataSource(
                    root: standardizedRoot,
                    generationDestination: generationDestination?.standardizedFileURL
                )
            )
        }

        func appendDirectory(_ directory: URL) {
            let standardizedDirectory = directory.standardizedFileURL
            let activeDirectory = DataGenerationStore.activeURL(for: standardizedDirectory).standardizedFileURL
            if activeDirectory != standardizedDirectory {
                appendSource(root: activeDirectory, generationDestination: standardizedDirectory)
            }
            appendSource(root: standardizedDirectory)
        }

        if let primaryDirectory {
            appendDirectory(primaryDirectory)
        }

        if let fallbackDirectories {
            for directory in fallbackDirectories {
                appendDirectory(directory)
            }
        } else {
            if let cacheDirectory = try? AppPaths.publicDataDirectory {
                appendDirectory(cacheDirectory)
            }
            if let legacyCacheDirectory = try? AppPaths.legacyPublicDataDirectoryURL {
                appendDirectory(legacyCacheDirectory)
            }

            appendBundleRoot(Bundle.module, subdirectory: "public", append: appendSource)
            appendBundleRoot(Bundle.module, subdirectory: nil, append: appendSource)
            appendBundleRoot(Bundle.main, subdirectory: "public", append: appendSource)
            appendBundleRoot(Bundle.main, subdirectory: nil, append: appendSource)

            appendSource(
                root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appending(path: "data/public", directoryHint: .isDirectory)
            )
        }

        return sources
    }

    nonisolated private static func appendBundleRoot(
        _ bundle: Bundle,
        subdirectory: String?,
        append: (URL, URL?) -> Void
    ) {
        guard let latestURL = bundle.url(
            forResource: "latest",
            withExtension: "json",
            subdirectory: subdirectory
        ) else {
            return
        }
        append(latestURL.deletingLastPathComponent(), nil)
    }

    nonisolated private static func synthesizedAnnouncements(from events: [GachaEventInfo]) -> [AnnouncementItem] {
        events
            .sorted { lhs, rhs in
                if lhs.from != rhs.from {
                    return lhs.from > rhs.from
                }
                if lhs.type != rhs.type {
                    return lhs.type < rhs.type
                }
                return lhs.name < rhs.name
            }
            .prefix(3)
            .map { event in
                AnnouncementItem(
                    id: "gacha-\(event.id)",
                    title: event.name,
                    subtitle: "\(event.version) · \(event.from.formatted(.dateTime.month().day())) - \(event.to.formatted(.dateTime.month().day()))",
                    url: nil,
                    bannerURL: event.bannerURL,
                    startsAt: event.from,
                    endsAt: event.to,
                    typeLabel: event.typeTitle
                )
            }
    }
}

private struct OverviewDataSource: Sendable {
    var root: URL
    var generationDestination: URL?
}
