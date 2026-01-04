# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**mapconductor-ios-sdk** is a Swift Package Manager library that provides a unified, SwiftUI-first API for working with multiple map providers (Google Maps and MapLibre) through a common abstraction layer. The SDK enables developers to write map code once and switch between providers at runtime without changing application code.

## Building and Testing

### Build the Package
```bash
swift build
```

### Open in Xcode
The repository is a Swift Package. Open `Package.swift` in Xcode to work with the package directly.

### Running Sample Apps

**MapConductorSample** (minimal example):
1. Create a new iOS App project in Xcode (iOS 14+)
2. Add this package as a local dependency
3. Copy files from `samples/MapConductorSample/` to your app target
4. Set Google Maps API key in `ContentView.swift`

**MapConductorSampleApp** (full-featured):
1. Open `samples/MapConductorSampleApp/MapConductorSampleApp.xcworkspace`
2. Set Google Maps API key in `samples/MapConductorSampleApp/Sources/SampleConfig.swift`
3. Select iOS 14+ simulator and run

Note: The sample app uses XcodeGen (project.yml) to generate the Xcode project.

## Architecture

### Multi-Backend Abstraction Pattern

The SDK uses **protocol-oriented design with generics** to support multiple map providers:

```
MapConductorCore (abstractions)
├── MapViewStateProtocol + MapViewState<T>
├── MapViewControllerProtocol
├── MapViewHolder + AnyMapViewHolder (type eraser)
└── MapDesignTypeProtocol

MapConductorForGoogleMaps (implementation)
├── GoogleMapViewState : MapViewState<GoogleMapDesignType>
├── GoogleMapView (SwiftUI wrapper)
└── GoogleMapViewController

MapConductorForMapLibre (implementation)
├── MapLibreViewState : MapViewState<MapLibreMapDesignType>
├── MapLibreMapView (SwiftUI wrapper)
└── MapLibreViewController
```

**Key Abstraction**: Each backend implements the same protocols from Core. Application code depends only on protocols, enabling provider switching at runtime.

### Core Module Structure

**mapconductor-core/Sources/MapConductorCore/**

- **MapViewContent.swift**: Result builder (`@MapViewContentBuilder`) for declarative overlay composition
- **MapViewState.swift**: Protocol + base class for reactive map state management
- **controller/**: Protocols for camera control and click event handling
- **marker/**: `MarkerState` (ObservableObject) with reactive properties using `@Published`
- **features/**: Geographic primitives (`GeoPoint`, `GeoRectBounds`)
- **map/**: Camera position, map holder, padding abstractions
- **info/**: SwiftUI-based info bubble components

### State Management Flow

```
Application modifies @StateObject MapViewState
    ↓
@Published properties trigger ObservableObject notifications
    ↓
SwiftUI calls body → @MapViewContentBuilder executes
    ↓
MapViewContent created with markers/infoBubbles
    ↓
GoogleMapView/MapLibreMapView (UIViewRepresentable) updates
    ↓
Coordinator syncs changes to underlying SDK (GMSMapView/MLNMapView)
```

### Reactive Marker System

**MarkerState** is an `ObservableObject` with `@Published` properties:
- Changes to icon, position, clickable, draggable trigger Combine publishers
- `asFlow()` method converts state to `AnyPublisher<MarkerFingerPrint, Never>`
- Coordinators subscribe to marker flows and sync changes to native markers
- Fingerprinting system (`MarkerFingerPrint`) prevents unnecessary updates via deduplication

### Result Builder Pattern

The `@MapViewContentBuilder` enables declarative map content:

```swift
GoogleMapView(state: state) {
    Marker(position: storeLocation, icon: .default())

    if showBubble {
        InfoBubble(marker: markerState) {
            Text("Store Details")
        }
    }

    ForEach(markers) { marker in
        Marker(state: marker)
    }
}
```

Supports: if/else, ForEach, optional unwrapping, array mapping.

### Type Erasure for Provider Independence

**AnyMapViewHolder** wraps backend-specific types (GMSMapView/MLNMapView):
- Stores closures for coordinate-to-screen and screen-to-coordinate conversions
- Allows application code to access map without knowing implementation
- Created via `init<H: MapViewHolderProtocol>(_ holder: H)` generic initializer

### Java-Compatible Hashing

The SDK uses custom `javaHash()` functions throughout for cross-platform consistency:
- **Purpose**: Maintains compatible marker IDs and fingerprints with Android counterpart
- **Where used**: `MarkerState.fingerPrint()`, `MarkerState.makeMarkerId()`
- **When modifying**: Preserve the 31-multiplier pattern and truncating behavior

## Common Development Patterns

### Adding a New Overlay Type

1. Define protocol in `mapconductor-core/Sources/MapConductorCore/`:
   ```swift
   public protocol YourOverlayProtocol {
       associatedtype DataType
       var flow: CurrentValueSubject<[String: DataType], Never> { get }
   }
   ```

2. Add to `MapViewContent`:
   ```swift
   public var yourOverlays: [YourOverlay] = []
   ```

3. Implement in both `MapConductorForGoogleMaps` and `MapConductorForMapLibre` coordinators

### Working with Camera Positions

Camera state is managed through `MapCameraPosition`:
- Contains: position (GeoPoint), zoom, bearing, tilt
- Animate via: `state.moveCameraTo(cameraPosition:durationMillis:)`
- Access current: `state.cameraPosition` (read-only, updated by coordinator)

### Custom Marker Icons

Two approaches:

**1. DefaultMarkerIcon** (generated at runtime):
```swift
Marker(position: location, icon: .default(
    size: 50,
    backgroundColor: .blue,
    strokeColor: .white,
    iconText: "A"
))
```

**2. BitmapIcon** (from UIImage):
```swift
let icon = BitmapIcon(image: UIImage(named: "pin")!)
Marker(position: location, icon: icon)
```

### Handling Marker Events

Attach handlers during construction or by mutating `MarkerState`:
```swift
let marker = MarkerState(position: location)
marker.onClick = { clickedMarker in
    print("Clicked: \(clickedMarker.id)")
}
marker.onDragEnd = { draggedMarker in
    // Update position in your data model
}
```

## Backend-Specific Implementation Notes

### Google Maps Implementation
- Uses `UIViewRepresentable` wrapping `GMSMapView`
- Marker synchronization via direct property assignment to `GMSMarker`
- Native animation support: `GMSCameraUpdate.animate()`
- Info bubbles can use native callouts or SwiftUI overlays

### MapLibre Implementation
- Uses `UIViewRepresentable` wrapping `MLNMapView`
- Markers use `MLNAnnotation` + custom `MLNAnnotationView`
- Custom `CameraAnimator` class (MapLibre lacks native animation)
- Info bubbles overlay markers using coordinate-to-screen conversion

### Switching Providers

Applications maintain separate state objects:
```swift
@StateObject var googleState = GoogleMapViewState()
@StateObject var mapLibreState = MapLibreViewState()

// Runtime switch
switch selectedProvider {
case .google:
    GoogleMapView(state: googleState) { /* content */ }
case .mapLibre:
    MapLibreMapView(state: mapLibreState) { /* content */ }
}
```

State objects are independent - no automatic state transfer between providers.

## Code Style and Conventions

### SwiftUI Representable Pattern
All map views use `UIViewRepresentable` with a `Coordinator` class that:
- Conforms to native SDK delegate protocols
- Manages subscriptions to marker/overlay flows
- Synchronizes SwiftUI state → native SDK state

### Published Properties
Use `@Published` for all mutable state in `ObservableObject` classes:
- Triggers automatic SwiftUI re-renders
- Enables Combine-based reactive flows
- Follow existing naming: `@Published private var _propertyName`

### Protocol Design
When adding protocols to Core:
- Use `associatedtype` for backend-specific types
- Provide protocol extensions for default implementations
- Keep protocols minimal - only shared behavior

### Initialization State Tracking
`InitState` enum tracks map view lifecycle:
- `NotStarted` → `Initializing` → `SdkInitialized` → `MapViewCreated` → `MapCreated`
- Used to prevent operations before map is ready
- Check `state.initState` before calling map methods

## Dependencies

- **ios-maps-sdk** (10.7.0): Google Maps SDK for iOS
- **maplibre-gl-native-distribution** (6.21.2): MapLibre Native for iOS
- **Minimum iOS version**: 17.0
- **Swift version**: 5.7+

## Platform Notes

### Swift Package Manager
The repository uses SPM exclusively - no CocoaPods or Carthage support.

### XcodeGen for Sample App
`MapConductorSampleApp` uses `project.yml` to generate `.xcodeproj`:
- Run `xcodegen` to regenerate project after structure changes
- The workspace includes both generated project and SPM dependencies

### API Keys
Google Maps requires an API key set at runtime:
```swift
GMSServices.provideAPIKey("YOUR_API_KEY")
```
MapLibre uses open style URLs (no key required for default styles).
