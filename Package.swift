// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PaimonToolbox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PaimonToolbox", targets: ["PaimonToolbox"])
    ],
    targets: [
        .executableTarget(
            name: "PaimonToolbox",
            path: ".",
            exclude: [
                ".codex",
                ".git",
                "data/manual",
                "data/releases",
                "dist",
                "docs",
                "promo_assets",
                "promo_frames",
                "LICENSE",
                "README.md",
                "THIRD_PARTY_NOTICES.md",
                "VERSION",
                "Entitlements",
                "App/Info.plist",
                "script",
                "Tests",
                "Widgets"
            ],
            sources: [
                "App",
                "Models",
                "Services",
                "Stores",
                "Support",
                "Views"
            ],
            resources: [
                .process("Resources"),
                .process("data/public")
            ]
        ),
        .testTarget(
            name: "PaimonToolboxTests",
            dependencies: ["PaimonToolbox"],
            path: "Tests/PaimonToolboxTests"
        )
    ]
)
