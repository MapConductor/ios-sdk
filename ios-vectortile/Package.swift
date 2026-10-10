// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0")
// `VectorStyleRasteriser` はあちらが宣言し、こちらが実装する
// （`VectorTileRasteriser`）。依存の向きはこの一方向だけ。
// `atPath:` の相対パスは**マニフェストの場所ではなくプロセスの CWD** から解決される。
// サンプルアプリのように外から path 参照されるとそこが別の場所になり、兄弟ディレクトリ
// を見つけられずリモートを取りに行って失敗する。`#filePath` から絶対パスで引く。
let vectorTileRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localStyleRoot = vectorTileRoot.deletingLastPathComponent().appendingPathComponent("ios-vectorstyle")
let usingLocalStyle = FileManager.default.fileExists(
    atPath: localStyleRoot.appendingPathComponent("Package.swift").path
)
let styleDependency: Package.Dependency = usingLocalStyle
    ? .package(path: localStyleRoot.path)
    : .package(url: "https://github.com/MapConductor/ios-vectorstyle", from: "1.0.0")

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
        styleDependency,
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
                .product(name: "MapConductorVectorStyle", package: "ios-vectorstyle"),
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
