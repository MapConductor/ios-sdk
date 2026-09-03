// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0")

let package = Package(
    name: "mapconductor-vectortile",
    platforms: [
        // See ios-sdk-core/Package.swift's comment: "15.0" must not be used here.
        .iOS("15.1"),
    ],
    products: [
        .library(
            name: "MapConductorVectorTile",
            type: frameworkLibraryType,
            targets: ["MapConductorVectorTile"]
        ),
    ],
    dependencies: [
        coreDependency,
    ],
    targets: [
        // The Rust renderer. Built and packaged by the mapconductor-vectortile
        // repo (scripts/build-ios.sh, then xcodebuild -create-xcframework) and
        // copied here by its scripts/sync-sdk.sh.
        .binaryTarget(name: "MvtRender", path: "MvtRender.xcframework"),
        .target(
            name: "MapConductorVectorTile",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                "MvtRender",
            ],
        ),
        .testTarget(
            name: "MapConductorVectorTileTests",
            dependencies: ["MapConductorVectorTile"],
            resources: [.process("Resources")],
        ),
    ]
)
