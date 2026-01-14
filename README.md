# MapConductor iOS SDK

MapConductor is a modular iOS SDK for building map-based applications with a unified API across multiple map providers.

This repository (**ios-sdk**) does **not** contain SDK source code.
Instead, it serves as the **entry point** for documentation, architecture overview, and sample projects.

Each feature is distributed as an independent Swift Package.

---

## Architecture Overview

MapConductor is designed as a set of composable modules:

- **Core**: common abstractions and shared logic
- **Map provider modules**: Google Maps, MapKit, MapLibre
- **Feature modules**: Heatmap, Marker Clustering, etc.

You can combine only the modules you need.

```
┌──────────────────────┐
│   Application Code   │
└─────────┬────────────┘
          │
┌─────────▼────────────┐
│  Feature Modules     │
│  - Heatmap           │
│  - Marker Clustering │
└─────────┬────────────┘
          │
┌─────────▼────────────┐
│  Map Provider Module │
│  - Google Maps       │
│  - MapKit            │
│  - MapLibre          │
└─────────┬────────────┘
          │
┌─────────▼────────────┐
│   Core Module        │
│   (ios-sdk-core)     │
└──────────────────────┘
```

------------------------------------------------------------------------------------------------

## Modules

### Core

| Module               | Description                                          |
|----------------------|------------------------------------------------------|
| ios-sdk-core         | Shared core abstractions and logic                   |

https://github.com/MapConductor/ios-sdk-core

### Map Provider Modules

| Provider             | Repository                                           |
|----------------------|------------------------------------------------------|
| Google Maps          | https://github.com/MapConductor/ios-for-googlemaps   |
| Apple MapKit         | https://github.com/MapConductor/ios-for-mapkit       |
| MapLibre             | https://github.com/MapConductor/ios-for-maplibre     |

Each module integrates a specific map SDK while conforming to the common Core interfaces.

### Feature Modules

| Feature              | Repository                                           |
|----------------------|------------------------------------------------------|
| Heatmap              | https://github.com/MapConductor/ios-heatmap          |
| Marker Clustering    | https://github.com/MapConductor/ios-marker-cluster   |

Feature modules are map-provider agnostic and depend only on [ios-sdk-core](https://github.com/MapConductor/ios-sdk-core).

------------------------------------------------------------------------------------------------

## Installation (Swift Package Manager)

You install MapConductor by combining the required modules in your app.

### Example: MapLibre + Heatmap

```swift
dependencies: [
    .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-for-maplibre", from: "1.0.0"),
    .package(url: "https://github.com/MapConductor/ios-heatmap", from: "1.0.0"),
],
```

Then add the products to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MapConductorCore", package: "ios-sdk-core"),
        .product(name: "MapConductorForMapLibre", package: "ios-for-maplibre"),
        .product(name: "MapConductorHeatmap", package: "ios-heatmap"),
    ]
)
```

------------------------------------------------------------------------------------------------

## Design Goals

- Modular: install only what you need

- Provider-agnostic features: reusable across map SDKs

- Swift Package Manager first

- Clear dependency boundaries

------------------------------------------------------------------------------------------------

## Samples

See [samples/MapConductorSampleApp](samples/MapConductorSampleApp) for a full-featured demo app showcasing all modules.

------------------------------------------------------------------------------------------------

## Status

This SDK is under active development.
Public APIs may evolve until the first stable release.

