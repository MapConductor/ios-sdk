// swift-tools-version: 5.9
import Foundation
import PackageDescription

// プロバイダの Package.swift はどれもこの形。コアがローカルにあればローカルを、
// 無ければ公開リポジトリを見る。
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4")

// android-for-openmobilemaps が使う mapscore と**同じ 4.0.0**。プラットフォーム間で
// メジャーがずれると、ズームの体系やレイヤーの挙動が食い違って比較にならなくなる。
//
// ## なぜローカル clone を先に見るのか
//
// maps-core 4.0.0 の Package.swift は、`external/djinni` に中身があると djinni を
// **相対パスの依存**へ切り替える。SwiftPM は git 依存を再帰 clone するので中身が入り、
// その結果「依存パッケージがローカルパス依存を持つ」形になって解決できない
// （`exhausted attempts to resolve the dependencies graph`）。
//
// そこで `../maps-core` へ自分で clone し、**djinni だけ空のまま**にしておく。
// すると maps-core は djinni を URL から取るようになり、解決が通る。
// 用意されていなければ公開リポジトリを見る（上流が直れば自動的にそちらへ戻る）。
// 手順は README.md を参照。ios-maps-sdk（Google）も同じくローカル clone 運用。
let usingLocalMapsCore = FileManager.default.fileExists(atPath: "../maps-core/Package.swift")
let mapsCoreDependency: Package.Dependency = usingLocalMapsCore
    ? .package(path: "../maps-core")
    : .package(url: "https://github.com/openmobilemaps/maps-core", from: "4.0.0")

let package = Package(
    name: "mapconductor-for-openmobilemaps",
    platforms: [
        // Open Mobile Maps は iOS 14 以上。コアが 15.1 を要求するのでそちらに合わせる。
        // （ios-sdk-core/Package.swift のコメントを参照。"15.0" は使えない）
        .iOS("15.1"),
    ],
    products: [
        .library(name: "MapConductorForOpenMobileMaps", targets: ["MapConductorForOpenMobileMaps"]),
    ],
    dependencies: [
        coreDependency,
        mapsCoreDependency,
    ],
    targets: [
        .target(
            name: "MapConductorForOpenMobileMaps",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                .product(name: "MapCore", package: "maps-core"),
            ]
        ),
        .testTarget(
            name: "MapConductorForOpenMobileMapsTests",
            dependencies: ["MapConductorForOpenMobileMaps"]
        ),
    ]
)
