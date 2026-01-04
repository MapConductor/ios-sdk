import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI
import UIKit

struct SimpleTextBubblePage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @State private var selectedMarker: MarkerState? = nil

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
            zoom: 10
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
            zoom: 10
        )
    )

    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
        extra: "San Francisco - The Golden Gate City",
        icon: DefaultMarkerIcon(fillColor: UIColor.systemBlue, label: "SF")
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                onMapClick: { _ in selectedMarker = nil },
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                }
            ) {
                Marker(state: markerState)

                if let marker = selectedMarker {
                    InfoBubble(marker: marker) {
                        Text(marker.extra as? String ?? "No information")
                            .foregroundColor(.accentColor)
                            .padding(4)
                    }
                }
            }
        }
        .onAppear {
            markerState.onClick = { marker in
                selectedMarker = marker
            }
        }
    }
}
