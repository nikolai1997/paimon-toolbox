import XCTest

final class PlannerViewLayoutTests: XCTestCase {
    func testPlannerHeaderAdaptsInsteadOfForcingSidebarCompression() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var plannerHeader: some View"))
        XCTAssertTrue(source.contains("private var plannerTargetControls: some View"))
        XCTAssertTrue(source.contains("private var plannerLevelControls: some View"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "ViewThatFits(in: .horizontal)").count - 1, 2)
    }

    func testLevelRangePickerKeepsVisibleTitleAboveControls() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 12)"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 5)"))
        XCTAssertTrue(source.contains(".frame(width: 132, alignment: .leading)"))
    }

    func testStatisticsViewShowsBossFightEstimateSummary() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("bossFightEstimates"))
        XCTAssertTrue(source.contains("头领预计"))
        XCTAssertTrue(source.contains("bossFightEstimateView"))
    }

    func testPlannerMaterialRowsResolveArtworkFromMetadata() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private func materialArtworkURL(for materialName: String) -> URL?"))
        XCTAssertTrue(source.contains("materialArtwork(name: requirement.materialName"))
        XCTAssertTrue(source.contains("materialArtwork(name: estimate.bossMaterialName"))
        XCTAssertTrue(source.contains("name: item.materialName"))
    }

    func testPlannerUsesCompactAdaptiveGridForMultiplePlans() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var plannerGridColumns: [GridItem]"))
        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 420, maximum: 560)"))
        XCTAssertTrue(source.contains("LazyVGrid(columns: plannerGridColumns"))
        XCTAssertTrue(source.contains("private var plansGrid: some View"))
    }

    func testPlannerMaterialRowsSupportCompletionToggleAndDirectInput() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PlannerView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private func requirementRow(plan: CultivationPlan, requirement: MaterialRequirement) -> some View"))
        XCTAssertTrue(source.contains("Button"))
        XCTAssertTrue(source.contains("completionSystemImage(for: requirement)"))
        XCTAssertTrue(source.contains("completionTint(for: requirement)"))
        XCTAssertTrue(source.contains("TextField(\"拥有\", value: binding(for: plan, requirement: requirement), format: .number)"))
        XCTAssertTrue(source.contains("private func toggleRequirementCompletion(plan: CultivationPlan, requirement: MaterialRequirement)"))
        XCTAssertTrue(source.contains("? 0"))
    }
}
