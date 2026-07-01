import Foundation

@MainActor
protocol OverviewDataServicing {
    func loadOverviewData() async throws -> OverviewData
}

struct LocalOverviewDataService: OverviewDataServicing {
    var publicDataDirectory: URL?

    init(publicDataDirectory: URL? = nil) {
        self.publicDataDirectory = publicDataDirectory
    }

    func loadOverviewData() async throws -> OverviewData {
        try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let gachaEvents = Self.decodeNonEmptyGachaEvents(
                decoder: decoder,
                directory: publicDataDirectory
            )
            let announcements = try Self.decodeAnnouncements(decoder: decoder, directory: publicDataDirectory)

            return OverviewData(
                latest: try Self.decodeIfAvailable(RemoteLatestInfo.self, fileName: "latest", decoder: decoder, directory: publicDataDirectory),
                announcements: announcements.isEmpty ? Self.synthesizedAnnouncements(from: gachaEvents) : announcements,
                gachaEvents: gachaEvents
            )
        }.value
    }

    nonisolated private static func decodeAnnouncements(decoder: JSONDecoder, directory: URL?) throws -> [AnnouncementItem] {
        do {
            return try decodeIfAvailable(AnnouncementFeed.self, fileName: "announcements", decoder: decoder, directory: directory)?.items ?? []
        } catch {
            return []
        }
    }

    nonisolated private static func decodeNonEmptyGachaEvents(decoder: JSONDecoder, directory: URL?) -> [GachaEventInfo] {
        for url in candidateURLs(fileName: "gacha-events", directory: directory) where FileManager.default.fileExists(atPath: url.path()) {
            do {
                let data = try Data(contentsOf: url)
                let events = try decoder.decode([GachaEventInfo].self, from: data)
                if !events.isEmpty {
                    return events
                }
            } catch {
                continue
            }
        }

        return []
    }

    nonisolated private static func decodeIfAvailable<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        decoder: JSONDecoder,
        directory: URL?
    ) throws -> T? {
        for url in candidateURLs(fileName: fileName, directory: directory) where FileManager.default.fileExists(atPath: url.path()) {
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(T.self, from: data)
            } catch {
                continue
            }
        }

        return nil
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

    nonisolated private static func candidateURLs(fileName: String, directory: URL?) -> [URL] {
        var urls: [URL] = []

        if let directory {
            urls.append(directory.appending(path: "\(fileName).json"))
        }

        if let cacheDirectory = try? AppPaths.publicDataDirectory {
            urls.append(cacheDirectory.appending(path: "\(fileName).json"))
        }

        if let legacyCacheDirectory = try? AppPaths.legacyPublicDataDirectoryURL {
            urls.append(legacyCacheDirectory.appending(path: "\(fileName).json"))
        }

        if let bundled = Bundle.module.url(forResource: fileName, withExtension: "json", subdirectory: "public") {
            urls.append(bundled)
        }

        if let bundled = Bundle.module.url(forResource: fileName, withExtension: "json") {
            urls.append(bundled)
        }

        if let bundled = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "public") {
            urls.append(bundled)
        }

        if let bundled = Bundle.main.url(forResource: fileName, withExtension: "json") {
            urls.append(bundled)
        }

        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "data/public/\(fileName).json"))

        return urls
    }
}
