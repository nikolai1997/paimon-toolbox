#!/usr/bin/env python3
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_NAME = "PaimonToolbox"
WIDGET_NAME = "PaimonToolboxWidgetsExtension"
PROJECT_DIR = ROOT / f"{PROJECT_NAME}.xcodeproj"
PBXPROJ_PATH = PROJECT_DIR / "project.pbxproj"
SCHEME_DIR = PROJECT_DIR / "xcshareddata" / "xcschemes"
APP_INFO_PLIST = ROOT / "App" / "Info.plist"
WIDGET_INFO_PLIST = ROOT / "Widgets" / "Info.plist"


class Ref(str):
    pass


def oid(key: str) -> Ref:
    return Ref(hashlib.sha1(key.encode("utf-8")).hexdigest()[:24].upper())


def quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def format_key(key: str) -> str:
    safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./$"
    if all(char in safe for char in key):
        return key
    return quote(key)


def format_value(value, indent: int = 0) -> str:
    pad = "\t" * indent
    next_pad = "\t" * (indent + 1)

    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, dict):
        lines = ["{"]
        for key in sorted(value):
            lines.append(f"{next_pad}{format_key(key)} = {format_value(value[key], indent + 1)};")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "()"
        lines = ["("]
        for item in value:
            lines.append(f"{next_pad}{format_value(item, indent + 1)},")
        lines.append(f"{pad})")
        return "\n".join(lines)
    if isinstance(value, int):
        return str(value)
    return quote(str(value))


def add_object(objects: dict, key: str, fields: dict) -> Ref:
    ref = oid(key)
    objects[ref] = fields
    return ref


def swift_files(paths):
    files = []
    for path in paths:
        files.extend(sorted((ROOT / path).rglob("*.swift")))
    return [file.relative_to(ROOT).as_posix() for file in files]


APP_SOURCES = swift_files(["App", "Models", "Services", "Stores", "Support", "Views"])
WIDGET_SOURCES = [
    "Models/WidgetSnapshot.swift",
    "Services/WidgetSnapshotStore.swift",
    "Support/AppPaths.swift",
    "Support/WidgetTimelineReloader.swift",
    "Views/Widgets/ToolboxWidgetViews.swift",
    "Widgets/PaimonToolboxWidgets.swift",
]
APP_RESOURCES = [
    ("Resources/AppIcon.icns", "image.icns", None),
    ("Resources/metadata.sample.json", "text.json", None),
    ("data/public", "folder", "public"),
]


def write_info_plists():
    APP_INFO_PLIST.write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>派蒙工具箱</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>派蒙工具箱</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.nikolai.paimon-toolbox.deep-link</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>paimontoolbox</string>
      </array>
    </dict>
  </array>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
""", encoding="utf-8")

    WIDGET_INFO_PLIST.write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>派蒙工具箱</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>派蒙工具箱 Widget</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
""", encoding="utf-8")


def build_settings_base(debug: bool) -> dict:
    settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_COMMA": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO" if debug else "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_TESTABILITY": "YES" if debug else "NO",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "6.0",
    }
    if debug:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        settings["GCC_OPTIMIZATION_LEVEL"] = "0"
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
    else:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
        settings["VALIDATE_PRODUCT"] = "YES"
    return settings


def target_settings(product: str, bundle_id: str, plist: str, entitlements: str, extension: bool = False) -> dict:
    settings = {
        "CODE_SIGN_ENTITLEMENTS": entitlements,
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Manual",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "2",
        "DEVELOPMENT_TEAM": "",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": plist,
        "LD_RUNPATH_SEARCH_PATHS": [
            "$(inherited)",
            "@executable_path/../Frameworks",
        ],
        "MARKETING_VERSION": "0.1.1",
        "PRODUCT_BUNDLE_IDENTIFIER": bundle_id,
        "PRODUCT_NAME": product,
        "PROVISIONING_PROFILE_SPECIFIER": "",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "XCODE_BUILD"],
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "6.0",
    }
    if extension:
        settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
        settings["ENABLE_APP_SANDBOX"] = "YES"
        settings["LD_RUNPATH_SEARCH_PATHS"] = [
            "$(inherited)",
            "@executable_path/../Frameworks",
            "@executable_path/../../../../Frameworks",
        ]
        settings["SKIP_INSTALL"] = "YES"
    else:
        settings["ENABLE_HARDENED_RUNTIME"] = "YES"
        settings["SKIP_INSTALL"] = "NO"
    return settings


def configuration_list(objects: dict, key: str, debug_settings: dict, release_settings: dict) -> Ref:
    debug = add_object(objects, f"{key}:Debug", {
        "isa": "XCBuildConfiguration",
        "buildSettings": debug_settings,
        "name": "Debug",
    })
    release = add_object(objects, f"{key}:Release", {
        "isa": "XCBuildConfiguration",
        "buildSettings": release_settings,
        "name": "Release",
    })
    return add_object(objects, f"{key}:ConfigList", {
        "isa": "XCConfigurationList",
        "buildConfigurations": [debug, release],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    })


def generate_project():
    objects = {}

    main_group = add_object(objects, "group:main", {
        "isa": "PBXGroup",
        "children": [],
        "sourceTree": "<group>",
    })
    products_group = add_object(objects, "group:products", {
        "isa": "PBXGroup",
        "children": [],
        "name": "Products",
        "sourceTree": "<group>",
    })

    product_app = add_object(objects, "product:app", {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": 0,
        "path": f"{PROJECT_NAME}.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    })
    product_widget = add_object(objects, "product:widget", {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.app-extension",
        "includeInIndex": 0,
        "path": f"{WIDGET_NAME}.appex",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    })
    objects[products_group]["children"] = [product_app, product_widget]

    file_refs = {}
    group_children = []
    all_project_files = sorted(set(
        APP_SOURCES
        + WIDGET_SOURCES
        + [path for path, _, _ in APP_RESOURCES]
        + [
            "App/Info.plist",
            "Widgets/Info.plist",
            "Entitlements/PaimonToolbox.entitlements",
            "Entitlements/PaimonToolboxWidgetsExtension.entitlements",
        ]
    ))

    for rel in all_project_files:
        ext = Path(rel).suffix
        if rel == "data/public":
            file_type = "folder"
            name = "public"
        elif ext == ".swift":
            file_type = "sourcecode.swift"
            name = None
        elif ext == ".plist":
            file_type = "text.plist.xml"
            name = None
        elif ext == ".entitlements":
            file_type = "text.plist.entitlements"
            name = None
        elif ext == ".icns":
            file_type = "image.icns"
            name = None
        else:
            file_type = "text.json"
            name = None
        fields = {
            "isa": "PBXFileReference",
            "lastKnownFileType": file_type,
            "path": rel,
            "sourceTree": "SOURCE_ROOT",
        }
        if name:
            fields["name"] = name
        file_refs[rel] = add_object(objects, f"fileref:{rel}", fields)
        group_children.append(file_refs[rel])

    objects[main_group]["children"] = group_children + [products_group]

    app_source_builds = [
        add_object(objects, f"buildfile:app-source:{rel}", {
            "isa": "PBXBuildFile",
            "fileRef": file_refs[rel],
        })
        for rel in APP_SOURCES
    ]
    widget_source_builds = [
        add_object(objects, f"buildfile:widget-source:{rel}", {
            "isa": "PBXBuildFile",
            "fileRef": file_refs[rel],
        })
        for rel in WIDGET_SOURCES
    ]
    app_resource_builds = [
        add_object(objects, f"buildfile:app-resource:{rel}", {
            "isa": "PBXBuildFile",
            "fileRef": file_refs[rel],
        })
        for rel, _, _ in APP_RESOURCES
    ]
    embedded_widget_build = add_object(objects, "buildfile:embed-widget", {
        "isa": "PBXBuildFile",
        "fileRef": product_widget,
        "settings": {
            "ATTRIBUTES": ["RemoveHeadersOnCopy", "CodeSignOnCopy"],
        },
    })

    app_sources_phase = add_object(objects, "phase:app:sources", {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": app_source_builds,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    app_frameworks_phase = add_object(objects, "phase:app:frameworks", {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    })
    app_resources_phase = add_object(objects, "phase:app:resources", {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": app_resource_builds,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    app_embed_phase = add_object(objects, "phase:app:embed-appex", {
        "isa": "PBXCopyFilesBuildPhase",
        "buildActionMask": 2147483647,
        "dstPath": "",
        "dstSubfolderSpec": 13,
        "files": [embedded_widget_build],
        "name": "Embed App Extensions",
        "runOnlyForDeploymentPostprocessing": 0,
    })

    widget_sources_phase = add_object(objects, "phase:widget:sources", {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": widget_source_builds,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    widget_frameworks_phase = add_object(objects, "phase:widget:frameworks", {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    })
    widget_resources_phase = add_object(objects, "phase:widget:resources", {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    })

    app_config = configuration_list(
        objects,
        "target:app",
        target_settings(PROJECT_NAME, "com.nikolai.paimon-toolbox", "App/Info.plist", "Entitlements/PaimonToolbox.entitlements"),
        target_settings(PROJECT_NAME, "com.nikolai.paimon-toolbox", "App/Info.plist", "Entitlements/PaimonToolbox.entitlements"),
    )
    widget_config = configuration_list(
        objects,
        "target:widget",
        target_settings(WIDGET_NAME, "com.nikolai.paimon-toolbox.widgets", "Widgets/Info.plist", "Entitlements/PaimonToolboxWidgetsExtension.entitlements", extension=True),
        target_settings(WIDGET_NAME, "com.nikolai.paimon-toolbox.widgets", "Widgets/Info.plist", "Entitlements/PaimonToolboxWidgetsExtension.entitlements", extension=True),
    )
    project_config = configuration_list(
        objects,
        "project",
        build_settings_base(debug=True),
        build_settings_base(debug=False),
    )

    app_target = oid("target:app:native")
    widget_target = oid("target:widget:native")
    container_proxy = add_object(objects, "dependency:widget:proxy", {
        "isa": "PBXContainerItemProxy",
        "containerPortal": oid("project:root"),
        "proxyType": 1,
        "remoteGlobalIDString": widget_target,
        "remoteInfo": WIDGET_NAME,
    })
    target_dependency = add_object(objects, "dependency:widget", {
        "isa": "PBXTargetDependency",
        "target": widget_target,
        "targetProxy": container_proxy,
    })

    objects[app_target] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": app_config,
        "buildPhases": [app_sources_phase, app_frameworks_phase, app_resources_phase, app_embed_phase],
        "buildRules": [],
        "dependencies": [target_dependency],
        "name": PROJECT_NAME,
        "productName": PROJECT_NAME,
        "productReference": product_app,
        "productType": "com.apple.product-type.application",
    }
    objects[widget_target] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": widget_config,
        "buildPhases": [widget_sources_phase, widget_frameworks_phase, widget_resources_phase],
        "buildRules": [],
        "dependencies": [],
        "name": WIDGET_NAME,
        "productName": WIDGET_NAME,
        "productReference": product_widget,
        "productType": "com.apple.product-type.app-extension",
    }

    project_ref = oid("project:root")
    objects[project_ref] = {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": "YES",
            "LastSwiftUpdateCheck": "2650",
            "LastUpgradeCheck": "2650",
            "ORGANIZATIONNAME": "Nikolai",
            "TargetAttributes": {
                app_target: {
                    "CreatedOnToolsVersion": "26.5",
                    "ProvisioningStyle": "Manual",
                    "SystemCapabilities": {
                        "com.apple.ApplicationGroups": {"enabled": 1},
                    },
                },
                widget_target: {
                    "CreatedOnToolsVersion": "26.5",
                    "ProvisioningStyle": "Manual",
                    "SystemCapabilities": {
                        "com.apple.ApplicationGroups": {"enabled": 1},
                    },
                },
            },
        },
        "buildConfigurationList": project_config,
        "compatibilityVersion": "Xcode 14.0",
        "developmentRegion": "en",
        "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base", "zh-Hans"],
        "mainGroup": main_group,
        "productRefGroup": products_group,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [app_target, widget_target],
    }

    content = [
        "// !$*UTF8*$!",
        "{",
        "\tarchiveVersion = 1;",
        "\tclasses = {};",
        "\tobjectVersion = 56;",
        "\tobjects = {",
    ]
    for ref in sorted(objects):
        content.append(f"\t\t{ref} = {format_value(objects[ref], 2)};")
    content.extend([
        "\t};",
        f"\trootObject = {project_ref};",
        "}",
        "",
    ])

    PROJECT_DIR.mkdir(exist_ok=True)
    PBXPROJ_PATH.write_text("\n".join(content), encoding="utf-8")
    write_scheme(app_target, widget_target)


def write_scheme(app_target: Ref, widget_target: Ref):
    SCHEME_DIR.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2650"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{widget_target}"
               BuildableName = "{WIDGET_NAME}.appex"
               BlueprintName = "{WIDGET_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (SCHEME_DIR / f"{PROJECT_NAME}.xcscheme").write_text(scheme, encoding="utf-8")


if __name__ == "__main__":
    write_info_plists()
    generate_project()
    print(PBXPROJ_PATH)
