// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DotListCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DotListCore", targets: ["DotListCore"])],
    targets: [
        .target(name: "DotListCore"),
        .testTarget(name: "DotListCoreTests", dependencies: ["DotListCore"])
    ]
)
