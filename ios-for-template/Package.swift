// swift-tools-version: 5.9
import Foundation
import PackageDescription

// プロバイダの Package.swift はどれもこの形。コアがローカルにあればローカルを、
// 無ければ公開リポジトリを見る。
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4")

let package = Package(
    name: "mapconductor-for-template",
    platforms: [
        // ios-sdk-core/Package.swift のコメントを参照。"15.0" は使えない。
        .iOS("15.1"),
    ],
    products: [
        .library(name: "MapConductorForTemplate", targets: ["MapConductorForTemplate"]),
    ],
    dependencies: [
        coreDependency,
        // 実際のドライバーはここに地図 SDK の依存を足す。
    ],
    targets: [
        .target(
            name: "MapConductorForTemplate",
            dependencies: [.product(name: "MapConductorCore", package: "ios-sdk-core")]
        ),
        .testTarget(
            name: "MapConductorForTemplateTests",
            dependencies: ["MapConductorForTemplate"]
        ),
    ]
)
