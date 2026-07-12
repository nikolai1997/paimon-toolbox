import CryptoKit
import Foundation

enum SelfCheck {
    static func runAndExit() -> Never {
        do {
            try run()
            print("Self-check passed")
            exit(0)
        } catch {
            fputs("Self-check failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        try verifyMetadata()
        try verifyBundledPublicData()
        try verifyGacha()
        try verifyUIGF()
        verifyPlanner()
    }

    static func verifyBundledPublicData() throws {
        if let publicDirectory = Bundle.module.url(forResource: "public", withExtension: nil) {
            try verifyPublicData(at: publicDirectory, allowedExtraJSONNames: [])
            return
        }
        guard let manifestURL = Bundle.module.url(forResource: "manifest", withExtension: "json") else {
            throw SelfCheckError.missingResource("public")
        }
        let resourceDirectory = manifestURL.deletingLastPathComponent()
        try verifyPublicData(at: resourceDirectory, allowedExtraJSONNames: ["metadata.sample.json"])
    }

    private static func verifyPublicData(at directory: URL, allowedExtraJSONNames: Set<String>) throws {
        let expectedNames = Set(RemoteDataFileKind.allCases.map(\.canonicalPath) + ["manifest.json"])
        let members = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let jsonMembers = members.filter { $0.pathExtension.lowercased() == "json" }
        let actualJSONNames = Set(jsonMembers.map(\.lastPathComponent))
        try require(actualJSONNames == expectedNames.union(allowedExtraJSONNames), "public data members mismatch")
        try require(jsonMembers.allSatisfy { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }, "public data contains a non-file member")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestURL = directory.appending(path: "manifest.json")
        let manifest = try decoder.decode(RemoteDataManifest.self, from: Data(contentsOf: manifestURL))
        try require(manifest.schemaVersion == RemoteDataManifest.currentSchemaVersion, "public manifest schema mismatch")
        try require(manifest.files.count == RemoteDataFileKind.allCases.count, "public manifest file count mismatch")

        var seenKinds: Set<RemoteDataFileKind> = []
        for file in manifest.files {
            try require(file.path == file.kind.canonicalPath, "public manifest path mismatch")
            try require(seenKinds.insert(file.kind).inserted, "public manifest kind duplicated")
            let data = try Data(contentsOf: directory.appending(path: file.path))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try require(digest.caseInsensitiveCompare(file.sha256) == .orderedSame, "public manifest hash mismatch")
        }
        try require(seenKinds == Set(RemoteDataFileKind.allCases), "public manifest kinds mismatch")

        _ = try decoder.decode(MetadataBundle.self, from: Data(contentsOf: directory.appending(path: "metadata.json")))
        _ = try decoder.decode(RemoteLatestInfo.self, from: Data(contentsOf: directory.appending(path: "latest.json")))
        _ = try decoder.decode(AnnouncementFeed.self, from: Data(contentsOf: directory.appending(path: "announcements.json")))
        _ = try decoder.decode([GachaEventInfo].self, from: Data(contentsOf: directory.appending(path: "gacha-events.json")))
        for name in ["characters.json", "weapons.json", "materials.json", "config.json"] {
            _ = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: name)))
        }
    }

    private static func verifyMetadata() throws {
        guard let url = Bundle.module.url(forResource: "metadata.sample", withExtension: "json") else {
            throw SelfCheckError.missingResource("metadata.sample.json")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MetadataBundle.self, from: data)
        let encoded = try JSONEncoder.iso8601.encode(bundle)
        _ = try decoder.decode(MetadataBundle.self, from: encoded)
        try require(Self.supportsMetadataVersion(bundle.version), "metadata version mismatch")
        try require(bundle.characters.count > 100, "metadata character count mismatch")
        try require(bundle.weapons.count > 200, "metadata weapon count mismatch")
        try require(bundle.materials.count > 800, "metadata material count mismatch")
        try require(bundle.characters.allSatisfy { $0.iconURL != nil && $0.portraitURL != nil }, "metadata character image mismatch")
        try require(bundle.weapons.allSatisfy { $0.iconURL != nil }, "metadata weapon image mismatch")
        try require(bundle.materials.allSatisfy { $0.iconURL != nil }, "metadata material image mismatch")
    }

    private static func verifyGacha() throws {
        let records = [
            GachaRecord(id: "1", time: Date(timeIntervalSince1970: 3), banner: .character, name: "冷刃", itemType: "武器", rarity: 3),
            GachaRecord(id: "2", time: Date(timeIntervalSince1970: 2), banner: .character, name: "夏洛蒂", itemType: "角色", rarity: 4),
            GachaRecord(id: "3", time: Date(timeIntervalSince1970: 1), banner: .character, name: "芙宁娜", itemType: "角色", rarity: 5)
        ]
        let summary = GachaSummary.make(from: records)
        try require(summary.totalPulls == 3, "gacha total mismatch")
        try require(summary.fiveStarCount == 1, "gacha five-star count mismatch")
        try require(summary.fourStarCount == 1, "gacha four-star count mismatch")
        try require(summary.pitySinceLastFiveStar == 2, "gacha pity mismatch")
    }

    private static func verifyUIGF() throws {
        let json = """
        {
          "info": {
            "uid": "100000001",
            "lang": "zh-cn",
            "export_time": "2026-06-24 12:00:00",
            "export_timestamp": 1782273600,
            "uigf_version": "v3.0"
          },
          "list": [
            {
              "id": "uigf-1",
              "time": "2026-06-24 12:01:00",
              "name": "芙宁娜",
              "item_type": "角色",
              "rank_type": "5",
              "gacha_type": "301",
              "uigf_gacha_type": "301"
            }
          ]
        }
        """
        let records = try GachaLogDocument.decodeRecords(from: Data(json.utf8))
        try require(records.count == 1, "uigf decode count mismatch")
        try require(records[0].banner == .character, "uigf banner mismatch")
        try require(records[0].rarity == 5, "uigf rarity mismatch")
        let exported = try GachaLogDocument.encodeUIGFRecords(records)
        let roundTrip = try GachaLogDocument.decodeRecords(from: exported)
        try require(roundTrip.count == 1, "uigf round-trip mismatch")
    }

    private static func verifyPlanner() {
        let plan = CultivationPlan(
            id: UUID(),
            targetName: "芙宁娜",
            targetKind: "角色",
            currentLevel: 80,
            targetLevel: 90,
            requirements: [
                MaterialRequirement(id: "a", materialName: "A", required: 10, owned: 4),
                MaterialRequirement(id: "b", materialName: "B", required: 10, owned: 12)
            ]
        )
        precondition(plan.requirements[0].remaining == 6, "planner remaining mismatch")
        precondition(plan.requirements[1].remaining == 0, "planner completed material mismatch")
        precondition(abs(plan.completion - 0.7) < 0.001, "planner completion mismatch")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfCheckError.failed(message)
        }
    }

    static func supportsMetadataVersion(_ version: String) -> Bool {
        version.hasPrefix("snap-") || version.hasPrefix("genshin-db-")
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum SelfCheckError: Error, CustomStringConvertible {
    case missingResource(String)
    case failed(String)

    var description: String {
        switch self {
        case .missingResource(let name): "missing resource \(name)"
        case .failed(let message): message
        }
    }
}
