import Foundation

enum GachaDashboardModule: String, CaseIterable, Identifiable, Codable {
    case insights
    case rarityDistribution
    case bannerDistribution
    case monthlyTrend
    case bannerPity
    case recentFiveStars
    case recordDetails

    var id: String {
        rawValue
    }
}

enum GachaDashboardLayout {
    static let defaultOrder: [GachaDashboardModule] = [
        .insights,
        .rarityDistribution,
        .bannerDistribution,
        .monthlyTrend,
        .bannerPity,
        .recentFiveStars,
        .recordDetails
    ]

    static func modules(from encoded: String) -> [GachaDashboardModule] {
        let canonicalized: [GachaDashboardModule] = encoded
            .split(separator: ",")
            .compactMap { raw -> GachaDashboardModule? in
                let value = String(raw)
                switch value {
                case "fiveStarRate", "fourStarRate", "averageFiveStarPity", "latestFiveStar":
                    return .insights
                default:
                    return GachaDashboardModule(rawValue: value)
                }
            }
        return normalized(canonicalized)
    }

    static func encoded(_ modules: [GachaDashboardModule]) -> String {
        normalized(modules).map(\.rawValue).joined(separator: ",")
    }

    static func move(
        _ dragged: GachaDashboardModule,
        before target: GachaDashboardModule,
        in modules: [GachaDashboardModule]
    ) -> [GachaDashboardModule] {
        guard dragged != target else {
            return normalized(modules)
        }

        var result = normalized(modules).filter { $0 != dragged }
        guard let targetIndex = result.firstIndex(of: target) else {
            result.append(dragged)
            return normalized(result)
        }
        result.insert(dragged, at: targetIndex)
        return normalized(result)
    }

    static func moveToEnd(
        _ dragged: GachaDashboardModule,
        in modules: [GachaDashboardModule]
    ) -> [GachaDashboardModule] {
        var result = normalized(modules).filter { $0 != dragged }
        result.append(dragged)
        return normalized(result)
    }

    private static func normalized(_ modules: [GachaDashboardModule]) -> [GachaDashboardModule] {
        var seen = Set<GachaDashboardModule>()
        var result: [GachaDashboardModule] = []
        for module in modules where !seen.contains(module) {
            result.append(module)
            seen.insert(module)
        }
        for module in defaultOrder where !seen.contains(module) {
            result.append(module)
        }
        return result
    }
}
