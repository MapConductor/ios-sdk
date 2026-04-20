# MapConductor iOS SDK Architecture

## Overview

MapConductor iOS SDK is a unified mapping library that provides a common API across multiple map providers. It abstracts provider-specific implementations behind consistent interfaces, allowing developers to switch between map SDKs with minimal code changes.

## Layered Architecture

### Layer 1: Unified API (MapConductor Core)

The core layer defines interfaces and common types that all map providers implement:

- **MapViewState**: Manages map view state and lifecycle
- **Marker, Circle, Polyline, Polygon, GroundImage**: Geometric overlays
- **GeoPoint, GeoRectBounds, MapCameraPosition**: Geospatial primitives

### Layer 2: Provider Adapters

Provider-specific modules adapt native map SDKs to the unified API:

- **MapConductorForGoogleMaps**: Wraps Google Maps SDK
- **MapConductorForMapbox**: Wraps Mapbox Maps SDK
- **MapConductorForMapKit**: Wraps Apple MapKit
- **MapConductorForMapLibre**: Wraps MapLibre SDK

Each adapter implements:
- MapViewStateProtocol
- Overlay controllers (MarkerController, CircleController, etc.)
- Provider-specific event handling

### Layer 3: Native Map SDKs

The underlying native map implementations:

- **Google Maps iOS SDK** (version 10.7.0)
- **Mapbox Maps iOS SDK** (version 11.14.3+)
- **Apple MapKit** (native iOS framework)
- **MapLibre GL Native** (version 6.21.2+)

## Module Dependency Graph

```
┌─────────────────────────────────────────────────┐
│             Application Layer                    │
└────────────────┬────────────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼─────────────────┐
│  Provider Module │  │  Utility Modules   │
│  (e.g., Google)  │  │  (Heatmap,         │
└───────┬──────────┘  │   Clustering)      │
        │             └──┬─────────────────┘
        └────────┬───────┘
                 │
        ┌────────▼──────────┐
        │ MapConductorCore  │
        └───────────────────┘
                 │
        ┌────────▼──────────┐
        │   Native SDKs     │
        │ (Google Maps,     │
        │  Mapbox, MapKit)  │
        └───────────────────┘
```

## Key Design Patterns

### 1. Provider-Independent Content

SwiftUI views can be written once and reused across all map providers:

```swift
struct MapContent: View {
    var body: some View {
        MapConductorMarker(
            state: MarkerState(position: geoPoint),
            title: "Point of Interest"
        )
        MapConductorCircle(
            state: CircleState(center: geoPoint, radius: 500)
        )
    }
}

// Use with any provider
GoogleMapView(state: googleMapState) {
    MapContent()
}

MapboxMapConductorView(state: mapboxMapState) {
    MapContent()
}
```

### 2. State Management

Separate state objects for overlays enable efficient updates and recomposition:

```swift
class MarkerState: ObservableObject {
    @Published var position: GeoPoint
    @Published var title: String?
    @Published var draggable: Bool = false
    // ... event handlers
}
```

### 3. MapViewHolder for Native Access

When MapConductor's unified API doesn't cover provider-specific features, MapViewHolder provides access to native SDKs:

```swift
let googleMapHolder = mapViewState.mapViewHolder
let nativeGoogleMap = googleMapHolder?.googleMap // Direct access
```

## File Structure

```
ios-sdk/
├── ios-sdk-core/
│   └── Sources/MapConductorCore/
│       ├── map/              # Core map interfaces
│       ├── marker/           # Marker state and controllers
│       ├── circle/           # Circle state and controllers
│       ├── polyline/         # Polyline state and controllers
│       ├── polygon/          # Polygon state and controllers
│       ├── groundimage/      # Ground overlay controllers
│       ├── infobubble/       # Info bubble support
│       └── core/             # GeoPoint, MapCameraPosition, etc.
│
├── ios-for-googlemaps/
│   └── Sources/MapConductorForGoogleMaps/
│       ├── GoogleMapView.swift
│       ├── GoogleMapViewState.swift
│       └── controllers/      # Provider-specific controllers
│
├── ios-for-mapbox/
│   └── Sources/MapConductorForMapbox/
│       ├── MapboxMapConductorView.swift
│       ├── MapboxViewState.swift
│       └── controllers/
│
├── ios-for-mapkit/
│   └── Sources/MapConductorForMapKit/
│       ├── MapKitMapView.swift
│       ├── MapKitViewState.swift
│       └── controllers/
│
├── ios-for-maplibre/
│   └── Sources/MapConductorForMapLibre/
│       ├── MapLibreMapView.swift
│       ├── MapLibreViewState.swift
│       └── controllers/
│
├── ios-heatmap/
│   └── Sources/MapConductorHeatmap/
│       ├── HeatmapOverlay.swift
│       └── HeatmapState.swift
│
└── ios-marker-cluster/
    └── Sources/MapConductorMarkerCluster/
        ├── MarkerClusterGroup.swift
        └── MarkerClusterGroupState.swift
```

## Component Communication

### Map View ↔ State

```
SwiftUI View
    │
    ├─ @StateObject mapViewState
    │
    └─ MapConductorView(state: mapViewState)
            │
            ├─ Reads camera position
            ├─ Reads overlay states
            └─ Triggers events
```

### Overlay Controller ↔ State

Each overlay (Marker, Circle, etc.) has:
- **State object**: Holds data and events (SwiftUI @Published)
- **Controller**: Native SDK integration, updates state
- **View**: Renders the overlay

## Lifecycle Management

### Initialization

1. User creates MapViewState instance
2. MapViewState initializes provider-specific implementations
3. Provider loads native map SDK
4. Map view hierarchy is established

### Runtime

1. Overlays added via SwiftUI children
2. State changes trigger controller updates
3. Native SDK updates map display
4. Events flow back through controllers to state handlers

### Cleanup

1. View is dismissed
2. MapViewState cleanup called
3. Native map SDK cleanup
4. Resources released

## Event Flow

```
User Interaction (tap, drag)
    │
    ▼
Native Map SDK
    │
    ▼
Provider Adapter (Controller)
    │
    ▼
State Object Event Handler
    │
    ▼
Application Logic
```

## Performance Considerations

1. **Marker Clustering**: For large marker sets, use MarkerClusterGroup
2. **Heatmaps**: Tile-based rendering for large datasets
3. **Reusable Content**: Extract common overlay patterns to separate views
4. **State Efficiency**: Minimize state updates using proper state isolation

## Future Extensions

- Custom styling per provider
- Advanced animation support
- Real-time location tracking
- Route and navigation features
- Advanced gesture handling
