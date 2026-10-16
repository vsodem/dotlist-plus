#!/usr/bin/env python3
"""Regenerate the dependency-free, shared iOS/macOS Xcode app project."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Apple/DotList.xcodeproj"
PROJECT.mkdir(parents=True, exist_ok=True)
objects = {}


def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def add(key, isa, **fields):
    identifier = uid(key)
    objects[identifier] = {"isa": isa, **fields}
    return identifier


def render(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(pad + "\t" + json.dumps(k) + " = " + render(v, indent + 1) + ";\n" for k, v in value.items()) + pad + "}"
    if isinstance(value, list):
        return "(\n" + "".join(pad + "\t" + render(v, indent + 1) + ",\n" for v in value) + pad + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)


source_builds = []
groups = []
for folder, path in [("App", "Apple/DotList"), ("Core", "Sources/DotListCore"), ("Storage", "Sources/DotListStorage")]:
    children = []
    for file in sorted((ROOT / path).glob("*.swift")):
        ref = add(str(file.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift", path=file.name, sourceTree="<group>")
        children.append(ref)
        source_builds.append(add("build-" + str(file.relative_to(ROOT)), "PBXBuildFile", fileRef=ref))
    groups.append(add(folder, "PBXGroup", children=children, name=folder,
                      path="DotList" if folder == "App" else "../" + path, sourceTree="<group>"))

resources = []
resource_refs = []
for name, path, file_type in [("Assets", "DotList/Assets.xcassets", "folder.assetcatalog"),
                              ("Rules", "../docs/APP_RULES.md", "net.daringfireball.markdown")]:
    ref = add(name, "PBXFileReference", lastKnownFileType=file_type, path=path, sourceTree="<group>")
    resource_refs.append(ref)
    resources.append(add("build-" + name, "PBXBuildFile", fileRef=ref))
product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="DotList.app", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=groups + resource_refs + [products], sourceTree="<group>")
sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
resource_phase = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)

project_configs = []
target_configs = []
for name in ["Debug", "Release"]:
    settings = {
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
    }
    if name == "Debug":
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
    project_configs.append(add("project-" + name, "XCBuildConfiguration", buildSettings=settings, name=name))
    target_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "NYZA33Z8N5",
        "CODE_SIGN_ENTITLEMENTS[sdk=iphone*]": "DotList/DotList-iOS.entitlements",
        "APS_ENVIRONMENT": "development" if name == "Debug" else "production",
        "ICLOUD_CONTAINER_ENVIRONMENT": "Development" if name == "Debug" else "Production",
        "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "DotList/DotList.entitlements",
        "COMBINE_HIDPI_IMAGES": "YES", "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_APP_SANDBOX": "YES", "ENABLE_HARDENED_RUNTIME": "YES",
        "ENABLE_USER_SELECTED_FILES": "readwrite", "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE[sdk=iphone*]": "DotList/Info-iOS.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": "Dot List",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../Frameworks"],
        "MARKETING_VERSION": "0.1.0", "PRODUCT_BUNDLE_IDENTIFIER": "com.vsodem.DotList",
        "PRODUCT_NAME": "$(TARGET_NAME)", "SDKROOT": "auto",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    target_configs.append(add("target-" + name, "XCBuildConfiguration", buildSettings=target_settings, name=name))
project_configuration = add("project-config", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target_configuration = add("target-config", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = add("target", "PBXNativeTarget", buildConfigurationList=target_configuration, buildPhases=[sources, frameworks, resource_phase], buildRules=[], dependencies=[], name="DotList", productName="DotList", productReference=product, productType="com.apple.product-type.application")
project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600", "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0", "DevelopmentTeam": "NYZA33Z8N5", "SystemCapabilities": {"com.apple.iCloud": {"enabled": 1}, "com.apple.Push": {"enabled": 1}, "com.apple.BackgroundModes": {"enabled": 1}}}}}, buildConfigurationList=project_configuration, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[target])
content = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + render(content) + "\n")
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DotList.app" BlueprintName="DotList" ReferencedContainer="container:DotList.xcodeproj"/>'
(scheme_dir / "DotList.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Apple/DotList.xcodeproj with", len(source_builds), "Swift sources.")
