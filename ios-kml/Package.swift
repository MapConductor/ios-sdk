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
    name: "mapconductor-kml",
    platforms: [
        // See ios-sdk-core/Package.swift's comment: "15.0" must not be used here.
        .iOS("15.1"),
    ],
    products: [
        .library(
            name: "MapConductorKML",
            type: frameworkLibraryType,
            targets: ["MapConductorKML"]
        ),
    ],
    dependencies: [
        coreDependency,
    ],
    targets: [
        .target(
            name: "MapConductorKML",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
            ],
            linkerSettings: [
                // KMZ (ZIP) の Deflate 展開に zlib を使う。
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "MapConductorKMLTests",
            dependencies: ["MapConductorKML"]
        ),
    ]
)
