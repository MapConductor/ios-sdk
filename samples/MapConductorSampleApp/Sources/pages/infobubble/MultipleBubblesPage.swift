import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI
import UIKit

struct MultipleBubblesPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @State private var selectedMarkers = Set<String>()

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
            zoom: 15
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
            zoom: 15
        )
    )

    private let markerState1 = MarkerState(
        position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
        id: "marker_1",
        extra: "Restaurant A",
        icon: DefaultMarkerIcon(fillColor: UIColor.systemRed, label: "1")
    )

    private let markerState2 = MarkerState(
        position: GeoPoint(latitude: 37.7849, longitude: -122.4094),
        id: "marker_2",
        extra: "Hotel B",
        icon: DefaultMarkerIcon(fillColor: UIColor.systemBlue, label: "2")
    )

    private let markerState3 = MarkerState(
        position: GeoPoint(latitude: 37.7649, longitude: -122.4294),
        id: "marker_3",
        extra: "Shop C",
        icon: DefaultMarkerIcon(fillColor: UIColor.systemGreen, label: "3")
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                onMapClick: { _ in
                    selectedMarkers = []
                },
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                }
            ) {
                Marker(state: markerState1)
                if selectedMarkers.contains(markerState1.id) {
                    InfoBubble(marker: markerState1) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(markerState1.extra as? String ?? "Unknown")
                                .font(.headline)
                            Text("Tap to close")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Marker(state: markerState2)
                if selectedMarkers.contains(markerState2.id) {
                    InfoBubble(marker: markerState2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(markerState2.extra as? String ?? "Unknown")
                                .font(.headline)
                            Text("Tap to close")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }

                Marker(state: markerState3)
                if selectedMarkers.contains(markerState3.id) {
                    InfoBubble(marker: markerState3) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(markerState3.extra as? String ?? "Unknown")
                                .font(.headline)
                            Text("Tap to close")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .onAppear {
            let markers = [markerState1, markerState2, markerState3]
            markers.forEach { marker in
                marker.onClick = { clicked in
                    if selectedMarkers.contains(clicked.id) {
                        selectedMarkers.remove(clicked.id)
                    } else {
                        selectedMarkers.insert(clicked.id)
                    }
                }
            }
            selectedMarkers = Set(markers.map { $0.id })
        }
    }
}
