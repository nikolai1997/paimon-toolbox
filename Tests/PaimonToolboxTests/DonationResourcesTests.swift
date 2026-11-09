import CryptoKit
import XCTest
@testable import PaimonToolbox

final class DonationResourcesTests: XCTestCase {
    func testBothPaymentCodesArePackagedAndDecodableImages() throws {
        try SelfCheck.verifyDonationImages()
    }

    func testBundledPaymentCodesMatchUserConfirmedOriginalFiles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for method in DonationPaymentMethod.allCases {
            let bundled = try Data(contentsOf: XCTUnwrap(method.imageURL))
            let original = try Data(contentsOf: root.appendingPathComponent("assets/donations/\(method.rawValue).png"))
            XCTAssertEqual(Data(SHA256.hash(data: bundled)), Data(SHA256.hash(data: original)), method.rawValue)
        }
    }
}
