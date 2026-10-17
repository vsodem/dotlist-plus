#!/usr/bin/env python3
"""Regenerate the dependency-free, shared iOS/macOS Xcode app project."""
import argparse
import plistlib
import sys
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = json.loads((ROOT / "product-identity.json").read_text())
CHECK = argparse.ArgumentParser()
CHECK.add_argument("--check", action="store_true")
CHECK = CHECK.parse_args().check
stale = []
def output(path, content):
    data = content.encode() if isinstance(content, str) else content
    if CHECK:
        if not path.exists() or path.read_bytes() != data:
            stale.append(str(path.relative_to(ROOT)))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
PROJECT = ROOT / "Apple/DotListPlus.xcodeproj"
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
for folder, path in [("App", "Apple/DotListPlus")]:
    children = []
    for file in sorted((ROOT / path).glob("*.swift")):
        ref = add(str(file.relative_to(ROOT)), "PBXFileReference", lastKnownFileType="sourcecode.swift", path=file.name, sourceTree="<group>")
        children.append(ref)
        source_builds.append(add("build-" + str(file.relative_to(ROOT)), "PBXBuildFile", fileRef=ref))
    groups.append(add(folder, "PBXGroup", children=children, name=folder,
                      path="DotListPlus" if folder == "App" else "../" + path, sourceTree="<group>"))

resources = []
resource_refs = []
for name, path, file_type in [("Assets", "DotListPlus/Assets.xcassets", "folder.assetcatalog"),
                              ("Rules", "../docs/APP_RULES.md", "net.daringfireball.markdown")]:
    ref = add(name, "PBXFileReference", lastKnownFileType=file_type, path=path, sourceTree="<group>")
    resource_refs.append(ref)
    resources.append(add("build-" + name, "PBXBuildFile", fileRef=ref))
product = add("product", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="DotListPlus.app", sourceTree="BUILT_PRODUCTS_DIR")
products = add("products", "PBXGroup", children=[product], name="Products", sourceTree="<group>")
main_group = add("main-group", "PBXGroup", children=groups + resource_refs + [products], sourceTree="<group>")
sources = add("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
package = add("package", "XCLocalSwiftPackageReference", relativePath="..")
package_products = [add("package-" + name, "XCSwiftPackageProductDependency", productName=name)
                    for name in ["DotListPlusCore", "DotListPlusApplication", "DotListPlusStorage", "DotListPlusCloudKit", "DotListPlusUI"]]
package_builds = [add("link-" + name, "PBXBuildFile", productRef=ref)
                  for name, ref in zip(["Core", "Application", "Storage", "CloudKit", "UI"], package_products)]
frameworks = add("frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=package_builds, runOnlyForDeploymentPostprocessing=0)
resource_phase = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)

project_configs = []
target_configs = []
for name in ["Debug", "Release"]:
    settings = {
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "ONLY_ACTIVE_ARCH": "YES" if name == "Debug" else "NO",
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
        "CODE_SIGN_ENTITLEMENTS[sdk=iphone*]": "DotListPlus/DotListPlus-iOS.entitlements",
        "APS_ENVIRONMENT": "development" if name == "Debug" else "production",
        "ICLOUD_CONTAINER_ENVIRONMENT": "Development" if name == "Debug" else "Production",
        "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "DotListPlus/DotListPlus.entitlements",
        "COMBINE_HIDPI_IMAGES": "YES", "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_APP_SANDBOX": "YES", "ENABLE_HARDENED_RUNTIME": "YES",
        "ENABLE_USER_SELECTED_FILES": "readwrite", "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE[sdk=iphone*]": "DotListPlus/Info-iOS.plist",
        "INFOPLIST_KEY_CFBundleDisplayName": IDENTITY["displayName"],
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
        "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../Frameworks"],
        "MARKETING_VERSION": "0.1.0", "PRODUCT_BUNDLE_IDENTIFIER": IDENTITY["bundleID"],
        "PRODUCT_NAME": "$(TARGET_NAME)", "SDKROOT": "auto",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
        "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    target_configs.append(add("target-" + name, "XCBuildConfiguration", buildSettings=target_settings, name=name))
project_configuration = add("project-config", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target_configuration = add("target-config", "XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target = add("target", "PBXNativeTarget", buildConfigurationList=target_configuration, buildPhases=[sources, frameworks, resource_phase], buildRules=[], dependencies=[], packageProductDependencies=package_products, name="DotListPlus", productName="DotListPlus", productReference=product, productType="com.apple.product-type.application")
project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600", "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0", "DevelopmentTeam": "NYZA33Z8N5", "SystemCapabilities": {"com.apple.iCloud": {"enabled": 1}, "com.apple.Push": {"enabled": 1}, "com.apple.BackgroundModes": {"enabled": 1}}}}}, buildConfigurationList=project_configuration, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", packageReferences=[package], targets=[target])
content = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
output(PROJECT / "project.pbxproj", "// !$*UTF8*$!\n" + render(content) + "\n")
scheme_dir = PROJECT / "xcshareddata/xcschemes"
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DotListPlus.app" BlueprintName="DotListPlus" ReferencedContainer="container:DotListPlus.xcodeproj"/>'
output(scheme_dir / "DotListPlus.xcscheme", f'''<?xml version="1.0" encoding="UTF-8"?>
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

constants = "// Generated by scripts/generate-xcode-project.py. Do not edit.\npublic enum ProductIdentity {\n"
for key, value in IDENTITY.items():
    constants += f"    public static let {key} = {json.dumps(value)}\n"
constants += "}\n"
output(ROOT / "Sources/DotListPlusCore/ProductIdentity.swift", constants)
for platform in ["macOS", "iOS"]:
    entitlements = {
        "com.apple.developer.icloud-container-identifiers": [IDENTITY["cloudContainerID"]],
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-environment": "$(ICLOUD_CONTAINER_ENVIRONMENT)",
    }
    if platform == "macOS":
        entitlements.update({"com.apple.security.app-sandbox": True,
            "com.apple.security.network.client": True, "com.apple.security.files.user-selected.read-write": True,
            "com.apple.developer.aps-environment": "$(APS_ENVIRONMENT)"})
    else:
        entitlements["aps-environment"] = "$(APS_ENVIRONMENT)"
    suffix = "-iOS" if platform == "iOS" else ""
    output(ROOT / f"Apple/DotListPlus/DotListPlus{suffix}.entitlements", plistlib.dumps(entitlements))
output(PROJECT / "project.xcworkspace/contents.xcworkspacedata", '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
if stale:
    print("Stale generated files: " + ", ".join(stale), file=sys.stderr)
    sys.exit(1)
print("Generated output is current." if CHECK else "Generated DotListPlus app, identity and entitlements.")
