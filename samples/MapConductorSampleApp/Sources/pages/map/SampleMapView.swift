import Foundation
import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case googleMaps = "Google Map"
    case mapLibre = "MapLibre"
    case mapKit = "MapKit"
    case mapbox = "Mapbox"
    case arcGIS = "ArcGIS"
    case here = "Here"

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
            if value == "mapbox" {
                return .mapbox
            }
            if value == "arcgis" || value == "arc_gis" {
                return .arcGIS
            }
            if value == "here" {
                return .here
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
            if value == "mapbox" {
                return .mapbox
            }
            if value == "arcgis" || value == "arc_gis" {
                return .arcGIS
            }
            if value == "here" {
                return .here
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
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState
    var onMapClick: ((GeoPoint) -> Void)? = nil
    var onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil
    var onCameraMove: ((MapCameraPosition) -> Void)? = nil
    var onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil
    var sdkInitialize: (() -> Void)?
    let content: () -> MapViewContent

    static func initializeAllSDKs() {
        if let apiKey = SampleConfig.googleMapsApiKey {
            GMSServices.provideAPIKey(apiKey)
        }
        if let accessToken = SampleConfig.mapboxAccessToken {
            initializeMapbox(accessToken: accessToken)
        }
        if let apiKey = SampleConfig.arcGISApiKey {
            _ = arcGISApiKeyInitialize(apiKey: apiKey)
        }
        if let accessKey = SampleConfig.hereAccessKeyId,
           let accessSecret = SampleConfig.hereAccessKeySecret {
            do {
                try hereKeyInitialize(accessKeyId: accessKey, accessKeySecret: accessSecret)
            } catch {
                NSLog("[MapConductor] HERE authentication failed: %@", String(describing: error))
            }
        }
    }

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        mapboxState: MapboxViewState,
        arcGISState: ArcGISMapViewState,
        hereState: HereMapViewState,
        onMapClick: ((GeoPoint) -> Void)? = nil,
        onCameraMoveStart: ((MapCameraPosition) -> Void)? = nil,
        onCameraMove: ((MapCameraPosition) -> Void)? = nil,
        onCameraMoveEnd: ((MapCameraPosition) -> Void)? = nil,
        sdkInitialize: (() -> Void)? = SampleMapView.initializeAllSDKs,
        @MapViewContentBuilder content: @escaping () -> MapViewContent
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.mapboxState = mapboxState
        self.arcGISState = arcGISState
        self.hereState = hereState
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
            if let _ = SampleConfig.googleMapsApiKey {
                GoogleMapView(
                    state: googleState,
                    onMapClick: onMapClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("Google Map is not available due to no API key")
            }
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

        case .mapbox:
            if let _ = SampleConfig.mapboxAccessToken {
                MapboxMapView(
                    state: mapboxState,
                    onMapClick: onMapClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("MapBox is not available due to no access token")
            }


        case .arcGIS:
            if let _ = SampleConfig.mapboxAccessToken {
                ArcGISMapView(
                    state: arcGISState,
                    onMapClick: onMapClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("MapBox is not available due to no api key")
            }
        
        
        case .here:
            if let keyId = SampleConfig.hereAccessKeyId,
               let keySecret = SampleConfig.hereAccessKeySecret  {
                HereMapView(
                    state: hereState,
                    onMapClick: onMapClick,
                    onCameraMoveStart: onCameraMoveStart,
                    onCameraMove: onCameraMove,
                    onCameraMoveEnd: onCameraMoveEnd,
                    sdkInitialize: sdkInitialize,
                    content: content
                )
            } else {
                Text("Here is not available due to no api key")
            }

        }
    }
}
