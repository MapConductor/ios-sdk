# MapConductor iOS SDK

A unified mapping library that provides a common API for multiple map providers including Google Maps, Mapbox, MapKit, ArcGIS, and MapLibre. Write once, deploy across all major mapping platforms.

## Features

- **Multi-Provider Support**: Seamlessly switch between Google Maps, Mapbox, MapKit, ArcGIS, and MapLibre with a single API
- **Unified Interface**: Common abstractions for markers, circles, polylines, polygons, ground overlays, heatmaps, and marker clustering
- **SwiftUI**: Modern iOS UI framework integration

## Module Structure

| Module | Package | Product | Description |
|---|---|---|---|
| `ios-sdk-core` | `mapconductor-core` | `MapConductorCore` | Core abstractions, geometry types, overlay states |
| `ios-for-googlemaps` | `mapconductor-for-googlemaps` | `MapConductorForGoogleMaps` | Google Maps implementation |
| `ios-for-mapbox` | `ios-for-mapbox` | `MapConductorForMapbox` | Mapbox implementation |
| `ios-for-mapkit` | `mapconductor-for-mapkit` | `MapConductorForMapKit` | Apple MapKit implementation |
| `ios-for-arcgis` | `mapconductor-for-arcgis` | `MapConductorForArcGIS` | ArcGIS implementation |
| `ios-for-maplibre` | `mapconductor-for-maplibre` | `MapConductorForMapLibre` | MapLibre implementation |
| `ios-heatmap` | `mapconductor-heatmap` | `MapConductorHeatmap` | Map-provider-agnostic heatmap overlay |
| `ios-marker-cluster` | `mapconductor-marker-cluster` | `MapConductorMarkerCluster` | Automatic marker clustering across all providers |

## Quick Start

### 1. Add Dependencies

Add the required packages in Xcode (File → Add Package Dependencies) or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-for-googlemaps", from: "1.0.0"), // or your chosen provider
],
```

Then add the products to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MapConductorCore", package: "ios-sdk-core"),
        .product(name: "MapConductorForGoogleMaps", package: "ios-for-googlemaps"),
    ]
)
```

### 2. Basic Usage

```swift
import SwiftUI
import MapConductorCore
import MapConductorForGoogleMaps

struct ContentView: View {
    @StateObject private var mapState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6762, longitude: 139.6503),
            zoom: 12
        )
    )

    var body: some View {
        GoogleMapView(state: mapState) {
            Marker(position: GeoPoint(latitude: 35.6762, longitude: 139.6503))
            Circle(
                center: GeoPoint(latitude: 35.6762, longitude: 139.6503),
                radiusMeters: 500
            )
        }
    }
}
```

### 3. Switch Map Providers

Simply change the state and view — all overlays work unchanged:

```swift
// Google Maps
GoogleMapView(state: googleMapState) { /* overlays */ }

// Mapbox
MapboxMapView(state: mapboxState) { /* overlays */ }

// Apple MapKit
MapKitMapView(state: mapKitState) { /* overlays */ }

// ArcGIS
ArcGISMapView(state: arcgisState) { /* overlays */ }

// MapLibre
MapLibreMapView(state: maplibreState) { /* overlays */ }
```

## Feature Implementation Status

|                     | Google Maps | Mapbox   | MapKit   | ArcGIS   | MapLibre |
|---------------------|-------------|----------|----------|----------|----------|
| Map                 | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker              | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Circle              | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polyline            | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polygon             | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| GroundImage         | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Heatmap             | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker Clustering   | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| RasterTileLayer     | &#x2611;    | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| VectorTileLayer     | &#x2610;    | &#x2610; | &#x2610; | &#x2610; | &#x2610; |

## Samples

See [samples/MapConductorSampleApp](samples/MapConductorSampleApp) for a full-featured demo app showcasing all modules.
