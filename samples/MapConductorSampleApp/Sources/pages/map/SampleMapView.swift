import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case googleMaps = "Google Map"
    case mapLibre = "MapLibre"
    case mapKit = "MapKit"

    var id: String { rawValue }
}

extension MapProvider {
    static func initial() -> MapProvider {
        let env = ProcessInfo.processInfo.environment
        if let value = env["MAPCONDUCTOR_SAMPLE_PROVIDER"]?.lowercased() {
            if value == "maplibre" || value == "map_libre" {
                return .mapLibre
            }
            if value == "googlemaps" || value == "google_maps" || value == "google" {
                return .googleMaps
            }
            if value == "mapkit" || value == "map_kit" {
                return .mapKit
            }
        }

        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--provider"), index + 1 < args.count {
            let value = args[index + 1].lowercased()
            if value == "maplibre" || value == "map_libre" {
                return .mapLibre
            }
            if value == "googlemaps" || value == "google_maps" || value == "google" {
                return .googleMaps
            }
            if value == "mapkit" || value == "map_kit" {
                return .mapKit
            }
        }

        return .googleMaps
    }
}

struct SampleMapView: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    var onMapClick: ((GeoPoint) -> Void)? = nil
    var onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil
    var onCameraMove: ((MapCameraPosition) -> Void)? = nil
    var onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil
    var sdkInitialize: (() -> Void)? = nil
    let content: () -> MapViewContent

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        onMapClick: ((GeoPoint) -> Void)? = nil,
        onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil,
        onCameraMove: ((MapCameraPosition) -> Void)? = nil,
        onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    var body: some View {
        switch provider {
        case .googleMaps:
            GoogleMapView(
                state: googleState,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: content
            )

        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                content: content
            )

        case .mapKit:
            MapKitMapView(
                state: mapKitState,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                content: content
            )
        }
    }
}
