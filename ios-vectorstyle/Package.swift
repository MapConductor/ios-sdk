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
    name: "mapconductor-vectorstyle",
    platforms: [
        // See ios-sdk-core/Package.swift's comment: "15.0" must not be used here.
        .iOS("15.1"),
    ],
    products: [
        .library(
            name: "MapConductorVectorStyle",
            type: frameworkLibraryType,
            targets: ["MapConductorVectorStyle"]
        ),
    ],
    dependencies: [
        coreDependency,
    ],
    targets: [
        // The Rust style compiler. Built and packaged by the
        // mapconductor-vectortile repo (scripts/build-ios-style.sh) and
        // copied here by its scripts/sync-sdk.sh.
        //
        // Its own binary rather than a corner of MvtRender: an app using
        // MapLibre, Mapbox or MapTiler adjusts a style without ever
        // rasterising one, and must not have to link the rasteriser to do it.
        .binaryTarget(name: "MvtStyle", path: "MvtStyle.xcframework"),
        // The header travels as a C target rather than inside the
        // XCFramework: Xcode merges every linked framework's Headers into
        // one include directory, and two module.modulemaps collide there --
        // which anything depending on both this and MvtRender would hit.
        .target(name: "CMvtStyle"),
        .target(
            name: "MapConductorVectorStyle",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                "CMvtStyle",
                "MvtStyle",
            ],
        ),
        .testTarget(
            name: "MapConductorVectorStyleTests",
            dependencies: ["MapConductorVectorStyle"],
            resources: [.process("Resources")],
        ),
    ]
)
