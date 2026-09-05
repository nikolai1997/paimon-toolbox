import XCTest
@testable import PaimonToolbox

final class DeskDeviceDiscoveryTests: XCTestCase {
    func testPrivateIPv4ClassificationUsedForDeskConnection() {
        XCTAssertTrue(DeskDeviceDiscovery.isPrivateIPv4("10.0.0.8"))
        XCTAssertTrue(DeskDeviceDiscovery.isPrivateIPv4("172.16.0.8"))
        XCTAssertTrue(DeskDeviceDiscovery.isPrivateIPv4("172.31.255.8"))
        XCTAssertTrue(DeskDeviceDiscovery.isPrivateIPv4("192.168.100.8"))

        XCTAssertFalse(DeskDeviceDiscovery.isPrivateIPv4("172.15.0.8"))
        XCTAssertFalse(DeskDeviceDiscovery.isPrivateIPv4("172.32.0.8"))
        XCTAssertFalse(DeskDeviceDiscovery.isPrivateIPv4("8.8.8.8"))
        XCTAssertFalse(DeskDeviceDiscovery.isPrivateIPv4("not-an-address"))
    }

    func testLegacyPairedDeviceRecordDecodesWithoutPresenceMetadata() throws {
        let data = Data(#"{"device_id":"desk-1","account_id":"account-1","access_token":"token","paired_at":0}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let record = try decoder.decode(DeskDirectDeviceRecord.self, from: data)

        XCTAssertEqual(record.deviceID, "desk-1")
        XCTAssertNil(record.name)
        XCTAssertNil(record.host)
        XCTAssertNil(record.lastSeenAt)
        XCTAssertNil(record.expiresAt)
    }
}
