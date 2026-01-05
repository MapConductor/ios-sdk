import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case googleMaps = "Google Map"
    case mapLibre = "MapLibre"

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
        }

        return .googleMaps
    }
}

struct SampleMapView: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    var onMapClick: ((GeoPoint) -> Void)? = nil
    var onCameraMove: ((MapCameraPosition) -> Void)? = nil
    var sdkInitialize: (() -> Void)? = nil
    let content: () -> MapViewContent
    
    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        onMapClick: ((GeoPoint) -> Void)? = nil,
        onCameraMove: ((MapCameraPosition) -> Void)? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.onMapClick = onMapClick
        self.onCameraMove = onCameraMove
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    var body: some View {
        switch provider {
        case .googleMaps:
            GoogleMapView(
                state: googleState,
                onMapClick: onMapClick,
                onCameraMove: onCameraMove,
                sdkInitialize: sdkInitialize,
                content: content
            )

        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                onMapClick: onMapClick,
                onCameraMove: onCameraMove,
                content: content
            )
        }
    }
}
