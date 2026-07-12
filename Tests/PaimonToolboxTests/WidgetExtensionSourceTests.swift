import XCTest

final class WidgetExtensionSourceTests: XCTestCase {
    func testWidgetTimelineNormalizesServerDatedSignInState() throws {
        let source = try source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertTrue(source.contains(".normalized(at: date)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testWidgetExtensionUsesSnapshotStoreAndDoesNotUseAccountServices() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Widgets/PaimonToolboxWidgets.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("WidgetKit"))
        XCTAssertTrue(source.contains("SmallSignInWidgetView"))
        XCTAssertTrue(source.contains("MediumGachaWidgetView"))
        XCTAssertTrue(source.contains("LargeToolboxWidgetView"))
        XCTAssertTrue(source.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(source.contains("LocalWidgetSnapshotStore"))
        XCTAssertFalse(source.contains("LocalAccountSessionService"))
        XCTAssertFalse(source.contains("GenshinSignInClient"))
        XCTAssertFalse(source.contains("AccountSecretStore"))
        XCTAssertFalse(source.contains("Keychain"))
    }

    func testWidgetPlaceholderUsesDedicatedSafePlaceholder() throws {
        let source = try source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertTrue(
            source.contains("""
            func placeholder(in context: Context) -> ToolboxWidgetEntry {
                    ToolboxWidgetEntry(date: Date(), snapshot: .empty, isSystemPlaceholder: true)
                }
            """)
        )
        XCTAssertTrue(source.contains("isSystemPlaceholder: false"))
        XCTAssertTrue(source.contains("entry.isSystemPlaceholder"))
    }

    func testWidgetExtensionSharedSourcesIncludeGlassStyleAndPureSnapshotDTO() throws {
        let sharedSources = [
            "Models/WidgetSnapshot.swift",
            "Services/WidgetSnapshotStore.swift",
            "Support/AppPaths.swift",
            "Support/WidgetTimelineReloader.swift",
            "Views/Widgets/ToolboxWidgetViews.swift",
            "Widgets/PaimonToolboxWidgets.swift"
        ]

        XCTAssertTrue(sharedSources.contains("Views/Widgets/ToolboxWidgetViews.swift"))
        XCTAssertFalse(sharedSources.contains("Views/Widgets/WidgetGlassStyle.swift"))
        XCTAssertFalse(sharedSources.contains("Models/WidgetSnapshotMapping.swift"))

        let widgetViewsSource = try source("Views/Widgets/ToolboxWidgetViews.swift")
        let widgetSource = try source("Widgets/PaimonToolboxWidgets.swift")

        XCTAssertFalse(widgetViewsSource.contains(".widgetGlass"))
        XCTAssertTrue(widgetViewsSource.contains("#if DEBUG && !WIDGET_EXTENSION_BUNDLE_BUILD"))
        XCTAssertTrue(widgetViewsSource.contains("#Preview(\"Small Widget\")"))
        XCTAssertTrue(widgetSource.contains(".containerBackground(for: .widget)"))
        XCTAssertTrue(widgetSource.contains("PaimonToolboxWidgetConfiguration.kind"))

        let snapshotSourceURL = repositoryRoot.appendingPathComponent("Models/WidgetSnapshot.swift")
        let snapshotSource = try String(contentsOf: snapshotSourceURL, encoding: .utf8)
        let appDomainTypeNames = [
            "LocalAccountStatus",
            "GachaRecord",
            "GachaSummary",
            "CultivationPlan"
        ]

        for typeName in appDomainTypeNames {
            XCTAssertFalse(snapshotSource.contains(typeName), "WidgetSnapshot.swift should not reference \(typeName)")
        }
    }

    func testBuildScriptsEmbedSignedWidgetExtension() throws {
        let runScript = try source("script/build_and_run.sh")
        let packageScript = try source("script/package_dmg.sh")
        let projectGenerator = try source("script/generate_xcode_project.py")
        let appEntitlements = try source("Entitlements/PaimonToolbox.entitlements")
        let widgetEntitlements = try source("Entitlements/PaimonToolboxWidgetsExtension.entitlements")

        XCTAssertTrue(runScript.contains("xcodebuild"))
        XCTAssertTrue(runScript.contains("$APP_NAME.xcodeproj"))
        XCTAssertTrue(runScript.contains("PaimonToolboxWidgetsExtension"))
        XCTAssertTrue(runScript.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(packageScript.contains("xcodebuild"))
        XCTAssertTrue(packageScript.contains("$APP_NAME.xcodeproj"))
        XCTAssertTrue(packageScript.contains("PaimonToolboxWidgetsExtension"))
        XCTAssertTrue(packageScript.contains("CODE_SIGNING_ALLOWED=NO"))
        XCTAssertTrue(projectGenerator.contains("com.apple.product-type.app-extension"))
        XCTAssertTrue(projectGenerator.contains("Embed App Extensions"))
        XCTAssertTrue(projectGenerator.contains("com.nikolai.paimon-toolbox.widgets"))
        XCTAssertTrue(projectGenerator.contains("Entitlements/PaimonToolboxWidgetsExtension.entitlements"))
        XCTAssertTrue(appEntitlements.contains("group.com.nikolai.paimon-toolbox"))
        XCTAssertFalse(appEntitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertFalse(appEntitlements.contains("com.apple.security.network.client"))
        XCTAssertTrue(widgetEntitlements.contains("com.apple.security.app-sandbox"))
        XCTAssertTrue(widgetEntitlements.contains("group.com.nikolai.paimon-toolbox"))
    }

    func testBuildScriptsDoNotDeepSignAppWithAppEntitlements() throws {
        let runScript = try source("script/build_and_run.sh")
        let packageScript = try source("script/package_dmg.sh")

        XCTAssertFalse(runScript.contains("codesign --force --deep --sign"))
        XCTAssertFalse(packageScript.contains("codesign --force --deep --sign"))
        XCTAssertTrue(runScript.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(packageScript.contains("codesign --verify --deep --strict"))
    }

    func testStandaloneWidgetBundleScriptIsPortableAndUsesConfigurationFlags() throws {
        let script = try source("script/build_widget_extension_bundle.sh")

        XCTAssertTrue(script.contains("tr '[:upper:]' '[:lower:]'"))
        XCTAssertTrue(script.contains("SWIFT_OPTIMIZATION="))
        XCTAssertTrue(script.contains("cd \"$ROOT_DIR\""))
        XCTAssertTrue(script.contains("-D WIDGET_EXTENSION_BUNDLE_BUILD"))
        XCTAssertFalse(script.contains("${CONFIGURATION_INPUT,,}"))
        XCTAssertFalse(script.contains("\"$CONFIGURATION\" \\\n    -Onone \\"))
    }

    func testLegacyWidgetExtensionScriptDelegatesToPortableBundleBuilder() throws {
        let script = try source("script/build_widget_extension.sh")

        XCTAssertTrue(script.contains("build_widget_extension_bundle.sh"))
        XCTAssertFalse(script.contains("xcrun swiftc"))
        XCTAssertFalse(script.contains("cat >\"$EXTENSION_INFO_PLIST\""))
    }

    func testDataUpdateToolDefaultsMatchCurrentPublicDataSourcePolicy() throws {
        let script = try source("script/update_remote_data.py")

        XCTAssertTrue(script.contains("Update PaimonToolbox remote data artifacts."))
        XCTAssertTrue(script.contains("default=\"genshin-db\""))
        XCTAssertTrue(script.contains("data source provider, default: genshin-db"))
        XCTAssertTrue(script.contains("default=\"snap-metadata\""))
        XCTAssertTrue(script.contains("gacha event source for genshin-db/official-manual mode, default: snap-metadata"))
        XCTAssertFalse(script.contains("Update GenshinToolbox remote data artifacts."))
        XCTAssertFalse(script.contains("data source provider, default: snap-metadata"))
    }

    func testPackageManifestExcludesLocalPromoAssetFoldersFromSwiftPMTarget() throws {
        let manifest = try source("Package.swift")
        let gitignore = try source(".gitignore")

        XCTAssertTrue(manifest.contains("\"promo_assets\""))
        XCTAssertTrue(manifest.contains("\"promo_frames\""))
        XCTAssertTrue(gitignore.contains("/promo_assets/"))
        XCTAssertTrue(gitignore.contains("/promo_frames/"))
    }

    func testAppDeclaresUtilitiesCategoryForReleasePackaging() throws {
        let infoPlist = try source("App/Info.plist")
        let projectGenerator = try source("script/generate_xcode_project.py")

        XCTAssertTrue(infoPlist.contains("<key>LSApplicationCategoryType</key>"))
        XCTAssertTrue(infoPlist.contains("<string>public.app-category.utilities</string>"))
        XCTAssertTrue(projectGenerator.contains("<key>LSApplicationCategoryType</key>"))
        XCTAssertTrue(projectGenerator.contains("<string>public.app-category.utilities</string>"))
    }

    func testDataUpdatePushDoesNotCommitIgnoredOfflineZip() throws {
        let script = try source("script/update_remote_data.py")
        let gitignore = try source(".gitignore")

        XCTAssertTrue(gitignore.contains("/data/releases/*.zip"))
        XCTAssertTrue(script.contains("commit_and_push([public_dir], args.commit_message, repository=root)"))
        XCTAssertFalse(script.contains("commit_and_push([public_dir, zip_path], args.commit_message)"))
    }

    func testInstallScriptRegistersInstalledWidgetExtension() throws {
        let installScript = try source("script/install_app.sh")

        XCTAssertTrue(installScript.contains("package_dmg.sh"))
        XCTAssertTrue(installScript.contains("INSTALL_DIR=\"${1:-/Applications}\""))
        XCTAssertTrue(installScript.contains("LaunchServices.framework"))
        XCTAssertTrue(installScript.contains("pluginkit -a"))
        XCTAssertFalse(installScript.contains("pluginkit -a \"$CURRENT_EXTENSION\" >/dev/null 2>&1 || true"))
        XCTAssertTrue(installScript.contains("PaimonToolboxWidgetsExtension.appex"))
        XCTAssertTrue(installScript.contains("pluginkit -m -AD -v -i"))
        XCTAssertTrue(installScript.contains("verify_widget_registration"))
        XCTAssertTrue(installScript.contains("expected_path=\"$(canonical_path \"$extension_path\")\""))
        XCTAssertTrue(installScript.contains("stop_process \"$APP_NAME\""))
        XCTAssertTrue(installScript.contains("stop_process \"$EXTENSION_NAME\""))
        XCTAssertTrue(installScript.contains("stop_process \"$LEGACY_APP_NAME\""))
        XCTAssertTrue(installScript.contains("stop_process \"$LEGACY_EXTENSION_NAME\""))
    }

    func testBuildRunScriptDoesNotLeaveDebugWidgetRegistered() throws {
        let runScript = try source("script/build_and_run.sh")

        XCTAssertTrue(runScript.contains("unregister_debug_widget"))
        XCTAssertTrue(runScript.contains("pluginkit -r \"$EXTENSION_BUNDLE\""))
    }

    func testVerifyModeChecksRealEmbeddedWidgetWithoutUnregisteringIt() throws {
        let runScript = try source("script/build_and_run.sh")
        let verifyStart = try XCTUnwrap(runScript.range(of: "--verify|verify)"))
        let verifyEnd = try XCTUnwrap(runScript.range(of: ";;", range: verifyStart.upperBound..<runScript.endIndex))
        let verifyBlock = String(runScript[verifyStart.lowerBound..<verifyEnd.upperBound])

        XCTAssertFalse(verifyBlock.contains("unregister_debug_widget"))
        XCTAssertTrue(verifyBlock.contains("$APP_BINARY\" --self-check"))
        XCTAssertTrue(verifyBlock.contains("codesign --verify --deep --strict \"$APP_BUNDLE\""))
        XCTAssertTrue(verifyBlock.contains("codesign --verify --strict \"$EXTENSION_BUNDLE\""))
        XCTAssertTrue(verifyBlock.contains("CFBundleIdentifier"))
        XCTAssertTrue(verifyBlock.contains("pluginkit -m -AD -v -i \"$WIDGET_BUNDLE_ID\""))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
