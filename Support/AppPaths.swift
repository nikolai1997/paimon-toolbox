import Foundation

enum AppPaths {
    static let appFolderName = "派蒙工具箱"
    static let legacyAppFolderName = "原神工具箱"

    static var appSupportDirectory: URL {
        get throws {
            let directory = try appSupportDirectoryURL()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static func appSupportDirectoryURL() throws -> URL {
        try appSupportDirectoryURL(folderName: appFolderName)
    }

    static func legacyAppSupportDirectoryURL() throws -> URL {
        try appSupportDirectoryURL(folderName: legacyAppFolderName)
    }

    private static func appSupportDirectoryURL(folderName: String) throws -> URL {
        let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        return base.appending(path: folderName, directoryHint: .isDirectory)
    }

    static var gachaRecordsURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "gacha-records.json")
        }
    }

    static var metadataCacheURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "metadata.json")
        }
    }

    static var legacyMetadataCacheURL: URL {
        get throws {
            try legacyAppSupportDirectoryURL().appending(path: "metadata.json")
        }
    }

    static var publicDataDirectory: URL {
        get throws {
            let directory = try appSupportDirectory.appending(path: "public-data", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static var legacyPublicDataDirectoryURL: URL {
        get throws {
            try legacyAppSupportDirectoryURL().appending(path: "public-data", directoryHint: .isDirectory)
        }
    }

    static var accountMetadataURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "account-metadata.json")
        }
    }

    static var accountSecretsURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "account-secrets.json")
        }
    }

    static var plannerURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "cultivation-plans.json")
        }
    }

    static var legacyPlannerURL: URL {
        get throws {
            try legacyAppSupportDirectoryURL().appending(path: "cultivation-plans.json")
        }
    }

    static var widgetSnapshotURL: URL {
        get throws {
            try appSupportDirectory.appending(path: "widget-snapshot.json")
        }
    }
}
