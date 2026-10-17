// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "DotListPlusCore", targets: ["DotListPlusCore"]),
    .library(name: "DotListPlusApplication", targets: ["DotListPlusApplication"]),
    .library(name: "DotListPlusStorage", targets: ["DotListPlusStorage"])
]
var targets: [Target] = [
    .target(name: "DotListPlusCore"),
    .target(name: "DotListPlusApplication", dependencies: ["DotListPlusCore"]),
    .target(name: "DotListPlusStorage", dependencies: ["DotListPlusApplication", "DotListPlusCore"]),
    .testTarget(name: "DotListPlusTests", dependencies: ["DotListPlusCore", "DotListPlusApplication", "DotListPlusStorage"])
]
#if os(macOS)
products += [
    .library(name: "DotListPlusCloudKit", targets: ["DotListPlusCloudKit"]),
    .library(name: "DotListPlusUI", targets: ["DotListPlusUI"])
]
targets += [
    .target(name: "DotListPlusCloudKit", dependencies: ["DotListPlusApplication", "DotListPlusCore"]),
    .target(name: "DotListPlusUI", dependencies: ["DotListPlusApplication", "DotListPlusCore"]),
    .testTarget(name: "DotListPlusAppleTests", dependencies: ["DotListPlusCloudKit", "DotListPlusUI", "DotListPlusApplication", "DotListPlusCore"])
]
#endif
let package = Package(name: "DotListPlus", platforms: [.iOS(.v17), .macOS(.v14)],
                      products: products, targets: targets)
