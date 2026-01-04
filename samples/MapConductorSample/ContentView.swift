import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

private enum MapProvider: String, CaseIterable, Identifiable {
    case googleMaps = "Google Maps"
    case mapLibre = "MapLibre"

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var provider: MapProvider = .googleMaps

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671)
    )

    private var activeState: any MapViewStateProtocol {
        switch provider {
        case .googleMaps:
            return googleState
        case .mapLibre:
            return mapLibreState
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mapView

            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $provider) {
                    ForEach(MapProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                HStack(spacing: 12) {
                    Button("Tokyo") {
                        moveCamera(
                            to: GeoPoint(latitude: 35.6812, longitude: 139.7671),
                            zoom: 12
                        )
                    }
                    Button("Kyoto") {
                        moveCamera(
                            to: GeoPoint(latitude: 35.0116, longitude: 135.7681),
                            zoom: 13
                        )
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.9))
            .cornerRadius(10)
            .padding()
        }
    }

    @ViewBuilder
    private var mapView: some View {
        switch provider {
        case .googleMaps:
            GoogleMapView(
                state: googleState,
                onMapClick: { point in markerState.position = point },
                sdkInitialize: {
                    GMSServices.provideAPIKey("<#Google Maps API Key#>")
                }
            ) {
                Marker(state: markerState)
                InfoBubble(marker: markerState) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tokyo Station")
                            .font(.headline)
                        Text("SwiftUI InfoBubble")
                            .font(.subheadline)
                    }
                }
            }

        case .mapLibre:
            MapLibreMapView(
                state: mapLibreState,
                onMapClick: { point in markerState.position = point }
            ) {
                Marker(state: markerState)
                InfoBubble(marker: markerState) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tokyo Station")
                            .font(.headline)
                        Text("SwiftUI InfoBubble")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private func moveCamera(to point: GeoPoint, zoom: Double) {
        let camera = MapCameraPosition(position: point, zoom: zoom)
        activeState.moveCameraTo(cameraPosition: camera, durationMillis: 600)
    }
}
