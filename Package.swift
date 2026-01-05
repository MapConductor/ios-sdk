// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mapconductor-ios-sdk",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "MapConductorCore",
            targets: ["MapConductorCore"]
        ),
        .library(
            name: "MapConductorForGoogleMaps",
            targets: ["MapConductorForGoogleMaps"]
        ),
        .library(
            name: "MapConductorForMapLibre",
            targets: ["MapConductorForMapLibre"]
        ),
        .library(
            name: "MapConductorTileServer",
            targets: ["MapConductorTileServer"]
        ),
        .library(
            name: "MapConductorHeatmap",
            targets: ["MapConductorHeatmap"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", exact: "10.7.0"),
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", exact: "6.21.2"),
    ],
    targets: [
        .target(
            name: "MapConductorCore",
            dependencies: [],
            path: "mapconductor-core/Sources/MapConductorCore"
        ),
        .target(
            name: "MapConductorForGoogleMaps",
            dependencies: [
                "MapConductorCore",
                .product(name: "GoogleMaps", package: "ios-maps-sdk"),
            ],
            path: "mapconductor-for-googlemaps/Sources/MapConductorForGoogleMaps"
        ),
        .target(
            name: "MapConductorForMapLibre",
            dependencies: [
                "MapConductorCore",
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
            ],
            path: "mapconductor-for-maplibre/Sources/MapConductorForMapLibre"
        ),
        .target(
            name: "MapConductorTileServer",
            dependencies: [],
            path: "mapconductor-tile-server/Sources/MapConductorTileServer"
        ),
        .target(
            name: "MapConductorHeatmap",
            dependencies: [
                "MapConductorCore",
                "MapConductorTileServer",
            ],
            path: "mapconductor-heatmap/Sources/MapConductorHeatmap"
        ),
    ]
)
