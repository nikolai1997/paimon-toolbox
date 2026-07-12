import XCTest
@testable import PaimonToolbox

@MainActor
final class OverviewDataServiceTests: XCTestCase {
    func testInvalidAnnouncementURLsDoNotDiscardOverviewData() async throws {
        let directory = try makeTemporaryDirectory()
        try writePublicData(
            to: directory,
            announcementsJSON: """
            {
              "items": [
                {
                  "id": "21788",
                  "title": "全新内容一览",
                  "subtitle": "版本现已开启",
                  "banner": "https://",
                  "contentURL": "https:notice/21788",
                  "startTime": "2026-07-01 07:00:00",
                  "endTime": "2026-08-12 06:00:00",
                  "type": "游戏公告"
                }
              ],
              "schemaVersion": 1,
              "updatedAt": "2026-07-10T07:56:00Z"
            }
            """,
            gachaEventsJSON: String(data: gachaEventsData(eventName: "镜中的茶宴"), encoding: .utf8)!
        )

        let data = try await LocalOverviewDataService(
            publicDataDirectory: directory,
            fallbackPublicDataDirectories: []
        ).loadOverviewData()

        XCTAssertEqual(data.gachaEvents.map(\.name), ["镜中的茶宴"])
        XCTAssertEqual(data.announcements.map(\.title), ["全新内容一览"])
        XCTAssertNil(data.announcements.first?.bannerURL)
        XCTAssertNil(data.announcements.first?.url)
        XCTAssertNotNil(data.announcements.first?.startsAt)
        XCTAssertNotNil(data.announcements.first?.endsAt)
        XCTAssertEqual(data.announcements.first?.typeLabel, "游戏公告")
    }

    func testMalformedAnnouncementFeedDoesNotDiscardValidGachaEvents() async throws {
        let directory = try makeTemporaryDirectory()
        try writePublicData(
            to: directory,
            announcementsJSON: "not-json",
            gachaEventsJSON: String(data: gachaEventsData(eventName: "镜中的茶宴"), encoding: .utf8)!
        )

        let data = try await LocalOverviewDataService(
            publicDataDirectory: directory,
            fallbackPublicDataDirectories: []
        ).loadOverviewData()

        XCTAssertEqual(data.gachaEvents.map(\.name), ["镜中的茶宴"])
        XCTAssertEqual(data.announcements.map(\.title), ["镜中的茶宴"])
    }

    func testLoadsGachaEventsFromPublicDataDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        try writePublicData(
            to: directory,
            announcementsJSON: emptyAnnouncementsJSON,
            gachaEventsJSON: """
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
            """
        )

        let data = try await LocalOverviewDataService(publicDataDirectory: directory).loadOverviewData()

        XCTAssertEqual(data.gachaEvents.map(\.name), ["霜锋夜白"])
    }

    func testSynthesizesAnnouncementsFromGachaEventsWhenAnnouncementFeedIsEmpty() async throws {
        let directory = try makeTemporaryDirectory()
        try writePublicData(
            to: directory,
            announcementsJSON: emptyAnnouncementsJSON,
            gachaEventsJSON: """
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
              },
              {
                "banner": null,
                "from": "2026-06-05T18:00:00+08:00",
                "name": "神铸赋形",
                "to": "2026-06-30T14:59:00+08:00",
                "type": 302,
                "upOrangeList": [11516],
                "upPurpleList": [],
                "version": "6.6"
              }
            ]
            """
        )

        let data = try await LocalOverviewDataService(publicDataDirectory: directory).loadOverviewData()

        XCTAssertEqual(data.announcements.map(\.title), ["霜锋夜白", "神铸赋形"])
        XCTAssertEqual(data.announcements.map(\.typeLabel), ["角色活动祈愿", "武器活动祈愿"])
    }

    func testCorruptRequiredGachaFileQuarantinesCurrentGenerationAndFallsBackAsAWhole() async throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicDataURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        try writePublicData(to: publicDataURL, eventName: "旧代卡池", announcementTitle: "旧代公告")
        try DataGenerationStore.publish(
            metadataData: Data("{}".utf8),
            publicFiles: [
                "latest.json": validLatestData,
                "announcements.json": announcementData(title: "新代公告"),
                "gacha-events.json": Data("not-json".utf8)
            ],
            metadataDestination: metadataURL,
            publicDestination: publicDataURL
        )

        let data = try await LocalOverviewDataService(publicDataDirectory: publicDataURL).loadOverviewData()

        XCTAssertEqual(data.gachaEvents.map(\.name), ["旧代卡池"])
        XCTAssertEqual(data.announcements.map(\.title), ["旧代公告"])
        XCTAssertEqual(DataGenerationStore.activeURL(for: publicDataURL), publicDataURL)
        XCTAssertEqual(try quarantineDirectories(in: directory).count, 1)
    }

    func testMissingRequiredFileQuarantinesCurrentGenerationAndFallsBackAsAWhole() async throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicDataURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        try writePublicData(to: publicDataURL, eventName: "旧代卡池", announcementTitle: "旧代公告")
        try DataGenerationStore.publish(
            metadataData: Data("{}".utf8),
            publicFiles: [
                "announcements.json": announcementData(title: "新代公告"),
                "gacha-events.json": gachaEventsData(eventName: "新代卡池")
            ],
            metadataDestination: metadataURL,
            publicDestination: publicDataURL
        )

        let data = try await LocalOverviewDataService(publicDataDirectory: publicDataURL).loadOverviewData()

        XCTAssertEqual(data.gachaEvents.map(\.name), ["旧代卡池"])
        XCTAssertEqual(data.announcements.map(\.title), ["旧代公告"])
        XCTAssertEqual(DataGenerationStore.activeURL(for: publicDataURL), publicDataURL)
        XCTAssertEqual(try quarantineDirectories(in: directory).count, 1)
    }

    func testAuthoritativeEmptyArraysDoNotFallBackToOlderSource() async throws {
        let directory = try makeTemporaryDirectory()
        let metadataURL = directory.appending(path: "metadata-cache.json")
        let publicDataURL = directory.appending(path: "public-data", directoryHint: .isDirectory)
        let fallbackURL = directory.appending(path: "fallback-public-data", directoryHint: .isDirectory)
        try writePublicData(to: fallbackURL, eventName: "旧代卡池", announcementTitle: "旧代公告")
        try DataGenerationStore.publish(
            metadataData: Data("{}".utf8),
            publicFiles: [
                "latest.json": validLatestData,
                "announcements.json": emptyAnnouncementsJSON.data(using: .utf8)!,
                "gacha-events.json": Data("[]".utf8)
            ],
            metadataDestination: metadataURL,
            publicDestination: publicDataURL
        )

        let data = try await LocalOverviewDataService(
            publicDataDirectory: publicDataURL,
            fallbackPublicDataDirectories: [fallbackURL]
        ).loadOverviewData()

        XCTAssertEqual(data.gachaEvents, [])
        XCTAssertEqual(data.announcements, [])
        XCTAssertNotEqual(DataGenerationStore.activeURL(for: publicDataURL), publicDataURL)
        XCTAssertEqual(try quarantineDirectories(in: directory).count, 0)
    }

    private var emptyAnnouncementsJSON: String {
        """
        {
          "items": [],
          "schemaVersion": 1,
          "updatedAt": "2026-06-24T15:00:31Z"
        }
        """
    }

    private func writePublicData(to directory: URL, announcementsJSON: String, gachaEventsJSON: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try validLatestData.write(to: directory.appending(path: "latest.json"))
        try announcementsJSON.data(using: .utf8)!.write(to: directory.appending(path: "announcements.json"))
        try gachaEventsJSON.data(using: .utf8)!.write(to: directory.appending(path: "gacha-events.json"))
    }

    private func writePublicData(to directory: URL, eventName: String, announcementTitle: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try validLatestData.write(to: directory.appending(path: "latest.json"))
        try announcementData(title: announcementTitle).write(to: directory.appending(path: "announcements.json"))
        try gachaEventsData(eventName: eventName).write(to: directory.appending(path: "gacha-events.json"))
    }

    private var validLatestData: Data {
        Data(#"{"schemaVersion":1,"dataVersion":"test","updatedAt":"2026-07-10T00:00:00Z","notes":"","required":false}"#.utf8)
    }

    private func announcementData(title: String) -> Data {
        Data(
            """
            {
              "items": [{"id":"test","title":"\(title)"}],
              "schemaVersion": 1,
              "updatedAt": "2026-07-10T00:00:00Z"
            }
            """.utf8
        )
    }

    private func gachaEventsData(eventName: String) -> Data {
        Data(
            """
            [
              {
                "banner": null,
                "from": "2026-07-01T18:00:00+08:00",
                "name": "\(eventName)",
                "to": "2026-07-30T14:59:00+08:00",
                "type": 301,
                "upOrangeList": [],
                "upPurpleList": [],
                "version": "6.8"
              }
            ]
            """.utf8
        )
    }

    private func quarantineDirectories(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".paimon-corrupt-generation-") }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
