import Foundation

@MainActor
protocol PlannerServicing {
    func loadPlans() async throws -> [CultivationPlan]
    func savePlans(_ plans: [CultivationPlan]) async throws
}

struct LocalPlannerService: PlannerServicing {
    private let plansURL: URL?
    private let legacyPlanURLs: [URL]

    init(plansURL: URL? = nil, legacyPlanURLs: [URL]? = nil) {
        self.plansURL = plansURL
        self.legacyPlanURLs = legacyPlanURLs ?? ((try? [AppPaths.legacyPlannerURL]) ?? [])
    }

    func loadPlans() async throws -> [CultivationPlan] {
        if let local = try? plannerFileURL(), FileManager.default.fileExists(atPath: local.path()) {
            let data = try Data(contentsOf: local)
            return try JSONDecoder().decode([CultivationPlan].self, from: data)
        }

        for legacyURL in legacyPlanURLs where FileManager.default.fileExists(atPath: legacyURL.path()) {
            guard let plans = try? JSONDecoder().decode([CultivationPlan].self, from: Data(contentsOf: legacyURL)) else {
                continue
            }
            try await savePlans(plans)
            return plans
        }

        return []
    }

    func savePlans(_ plans: [CultivationPlan]) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(plans)
        let url = try plannerFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func plannerFileURL() throws -> URL {
        try plansURL ?? AppPaths.plannerURL
    }
}
