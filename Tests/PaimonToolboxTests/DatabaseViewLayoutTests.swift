import XCTest

final class DatabaseViewLayoutTests: XCTestCase {
    func testCharacterAscensionMaterialsResolveArtworkFromMetadata() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/DatabaseView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var materialsByName: [String: MaterialItem]"))
        XCTAssertTrue(source.contains("characterMaterialRow(name: material)"))
        XCTAssertTrue(source.contains("MetadataArtworkView(url: item?.iconURL"))
    }
}
