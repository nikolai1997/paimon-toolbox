import Foundation

struct MetadataBundle: Codable, Equatable {
    var version: String
    var updatedAt: Date
    var characters: [GameCharacter]
    var weapons: [Weapon]
    var materials: [MaterialItem]
}

struct RemoteDataManifest: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var files: [RemoteDataFile]
}

struct RemoteDataFile: Codable, Equatable {
    var path: String
    var sha256: String
    var kind: RemoteDataFileKind
}

enum RemoteDataFileKind: String, Codable, Equatable {
    case metadata
    case characters
    case weapons
    case materials
    case gachaEvents
    case config
    case announcements
    case latest
}

struct GameCharacter: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var element: String
    var weaponType: String
    var rarity: Int
    var region: String
    var iconURL: URL? = nil
    var portraitURL: URL? = nil
    var materials: [String]
    var cultivation: CharacterCultivationMaterials? = nil
}

struct CharacterCultivationMaterials: Codable, Equatable {
    var ascensionGemNames: [String]
    var bossMaterialName: String
    var localSpecialtyName: String
    var commonMaterialNames: [String]
    var talentBookNames: [String]
    var weeklyBossMaterialName: String

    var hasExactMaterialTiers: Bool {
        ascensionGemNames.count >= 4
            && !bossMaterialName.isEmpty
            && !localSpecialtyName.isEmpty
            && commonMaterialNames.count >= 3
            && talentBookNames.count >= 3
            && !weeklyBossMaterialName.isEmpty
    }
}

struct Weapon: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var type: String
    var rarity: Int
    var stat: String
    var iconURL: URL? = nil
    var materials: [String]
}

struct MaterialItem: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var category: String
    var source: String
    var iconURL: URL? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case source
        case iconURL
    }

    init(id: Int, name: String, category: String, source: String, iconURL: URL? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.source = source
        self.iconURL = iconURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decode(String.self, forKey: .source)
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)

        if let value = try? container.decode(String.self, forKey: .category) {
            category = value
        } else if let value = try? container.decode(Int.self, forKey: .category) {
            category = String(value)
        } else if let value = try? container.decode(Double.self, forKey: .category) {
            category = String(value)
        } else {
            category = ""
        }
    }
}
