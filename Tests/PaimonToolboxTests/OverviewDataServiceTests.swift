import XCTest
@testable import PaimonToolbox

@MainActor
final class OverviewDataServiceTests: XCTestCase {
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
        try announcementsJSON.data(using: .utf8)!.write(to: directory.appending(path: "announcements.json"))
        try gachaEventsJSON.data(using: .utf8)!.write(to: directory.appending(path: "gacha-events.json"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
