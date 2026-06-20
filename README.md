# MapConductor iOS SDK

- [Japanese Doc](./README.ja.md)
- [Spanish Doc](./README.es-419.md)

**One iOS map API for multiple map providers.**

MapConductor iOS SDK is a mapping library for iOS that lets you work with multiple map SDKs through a single, consistent SwiftUI API.

Instead of writing different map code for Google Maps, Mapbox, Apple MapKit, ArcGIS, HERE Maps, and MapLibre, MapConductor provides shared abstractions for maps, camera state, markers, shapes, overlays, and advanced map features.

Write your map UI once.
Choose the map provider that fits your product.

---

## Why MapConductor?

Mobile map development often becomes tightly coupled to a specific map SDK. Each provider has its own API design, lifecycle model, rendering behavior, and feature set. This makes it hard to switch providers, support multiple map backends, or keep map-related code clean in a modern SwiftUI application.

MapConductor solves this by providing a common layer on top of major iOS map SDKs.

With MapConductor, you can:

* Use a SwiftUI-first API for map UI
* Switch between supported map providers with less rewrite work
* Share the same marker, circle, polyline, polygon, and overlay logic
* Build provider-independent map features such as heatmaps and marker clustering
* Keep your application code focused on map behavior, not SDK-specific differences

![](./images/en-comic-why-mapconductor.jpg)

---

## Supported Map Providers

MapConductor currently supports the following iOS map providers:

| Provider        | Package                       | Product                        |
| ---------------- | ------------------------------ | ------------------------------- |
| Google Maps     | `ios-for-googlemaps`          | `MapConductorForGoogleMaps`    |
| Mapbox          | `ios-for-mapbox`              | `MapConductorForMapbox`        |
| Apple MapKit    | `ios-for-mapkit`              | `MapConductorForMapKit`        |
| ArcGIS          | `ios-for-arcgis`              | `MapConductorForArcGIS`        |
| HERE Maps       | `ios-for-here`                | `MapConductorForHERE`          |
| MapLibre        | `ios-for-maplibre`            | `MapConductorForMapLibre`      |

You can choose one provider for your app, or structure your code so that the provider can be changed later.

---

## Core Features

MapConductor provides a unified API for common map UI and geospatial features:

* Map view components for multiple providers
* Camera state and camera position
* Markers
* Custom marker icons
* Circles with meter-based radius
* Polylines
* Polygons
* Ground images
* Raster tile layers
* Heatmaps
* Marker clustering
* GeoJSON layers
* Shared geometry types such as `GeoPoint`
* Reactive state management for map objects, built on SwiftUI

The goal is not only to wrap each provider SDK, but also to provide consistent behavior where possible across different map engines.

---

## Installation

Add the required packages in Xcode (File → Add Package Dependencies) or directly in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.5"),
    .package(url: "https://github.com/MapConductor/ios-for-googlemaps", from: "1.0.5"), // or your chosen provider

    // Optional feature packages
    .package(url: "https://github.com/MapConductor/ios-heatmap", from: "1.0.3"),
    .package(url: "https://github.com/MapConductor/ios-marker-cluster", from: "1.0.2"),
    .package(url: "https://github.com/MapConductor/ios-geojson-layer", from: "1.0.0"),
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

Each map provider may require its own API key, access token, or Xcode project configuration (such as Info.plist entries). Please check the setup guide for the provider you are using.

---

## Basic Example

The following example shows a simple SwiftUI map with a marker and a circle.

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

This example uses Google Maps, but the map objects are written using MapConductor concepts. The same overlay logic can be adapted to other supported providers.

---

## Switching Map Providers

One of the main ideas behind MapConductor is that your map overlays should not have to be rewritten when you change map providers.

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

// HERE Maps
HEREMapView(state: hereMapState) { /* overlays */ }

// MapLibre
MapLibreMapView(state: maplibreState) { /* overlays */ }
```

Your reusable map content can contain markers, circles, polylines, polygons, heatmaps, clusters, or other MapConductor components, regardless of which provider view renders them.

Provider-specific setup is still required, but your application-level map UI can stay much more portable.

---

## Module Overview

| Module                       | Package                          | Product                         | Description                                                          |
| ----------------------------- | --------------------------------- | --------------------------------- | --------------------------------------------------------------------- |
| `ios-sdk-core`                | `mapconductor-core`               | `MapConductorCore`               | Core abstractions, geometry types, overlay states                    |
| `ios-for-googlemaps`          | `mapconductor-for-googlemaps`     | `MapConductorForGoogleMaps`      | Google Maps provider implementation                                  |
| `ios-for-mapbox`              | `ios-for-mapbox`                  | `MapConductorForMapbox`          | Mapbox provider implementation                                       |
| `ios-for-mapkit`              | `mapconductor-for-mapkit`         | `MapConductorForMapKit`          | Apple MapKit provider implementation                                 |
| `ios-for-arcgis`              | `mapconductor-for-arcgis`         | `MapConductorForArcGIS`          | ArcGIS provider implementation                                       |
| `ios-for-here`                | `mapconductor-for-here`           | `MapConductorForHERE`            | HERE Maps provider implementation                                    |
| `ios-for-maplibre`            | `mapconductor-for-maplibre`       | `MapConductorForMapLibre`        | MapLibre provider implementation                                     |
| `ios-heatmap`                 | `mapconductor-heatmap`            | `MapConductorHeatmap`            | Provider-independent heatmap overlay                                 |
| `ios-marker-cluster`          | `mapconductor-marker-cluster`     | `MapConductorMarkerCluster`      | Marker clustering support                                            |
| `ios-geojson-layer`           | `mapconductor-geojson-layer`      | `MapConductorGeoJSONLayer`       | GeoJSON layer support                                                 |

---

## Feature Status

| Feature           | Google Maps | Mapbox   | MapKit   | ArcGIS   | HERE Maps | MapLibre |
| ------------------ | -----------: | --------: | --------: | --------: | --------: | --------: |
| Map               |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Circle            |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polyline          |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Polygon           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Ground Image      |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Heatmap           |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Marker Clustering |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Raster Tile Layer |     &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; | &#x2611; |
| Vector Tile Layer |     &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; | &#x2610; |

MapConductor is actively developed. Please check the documentation and release notes for the latest provider-specific behavior and limitations.

---

## Who Is This For?

MapConductor is useful if you are:

* Building an iOS app with SwiftUI and maps
* Evaluating multiple map providers
* Planning a possible migration from one map SDK to another
* Maintaining map features across different customer or regional requirements
* Building reusable map UI components
* Looking for an open-source abstraction layer for mobile maps

It is especially helpful when you want your application code to describe what should appear on the map, rather than how each provider SDK expects that feature to be implemented.

---

## Samples

See [samples/MapConductorSampleApp](samples/MapConductorSampleApp) for a full-featured demo app showcasing all modules.

---

## Project Status

MapConductor iOS SDK is released and under active development.

The project aims to make map development more flexible, portable, and SwiftUI-friendly across major iOS map providers. Some advanced features may still be experimental or may have provider-specific differences.

Feedback, issues, and contributions are welcome.

---

## License

MapConductor iOS SDK is released under the Apache License 2.0.
