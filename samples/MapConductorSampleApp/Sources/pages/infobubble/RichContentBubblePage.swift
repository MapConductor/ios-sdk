import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

private struct LocationInfo {
    let name: String
    let description: String
    let rating: Double
}

struct RichContentBubblePage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @Environment(\.colorScheme) private var colorScheme
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

    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 37.7749, longitude: -122.4194),
            zoom: 10
        )
    )

    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 37.7694, longitude: -122.4862),
        extra: LocationInfo(
            name: "Golden Gate Park",
            description: "A large urban park with gardens, museums, and recreational areas.",
            rating: 4.5
        ),
        icon: DefaultMarkerIcon(fillColor: UIColor.systemGreen, label: "P")
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
            mapKitState: mapKitState,
                onMapClick: { _ in selectedMarker = nil },
                sdkInitialize: {
                    GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                }
            ) {
                Marker(state: markerState)

                if let marker = selectedMarker,
                   let info = marker.extra as? LocationInfo {
                    InfoBubble(marker: marker, style: bubbleStyle()) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(info.name)
                                .font(.headline)
                                .fontWeight(.bold)

                            Text(info.description)
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .gray)

                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { index in
                                    Image(systemName: "star.fill")
                                        .foregroundColor(index < Int(info.rating) ? .yellow : .gray)
                                        .font(.system(size: 12))
                                }
                                Text(String(format: " %.1f/5", info.rating))
                                    .font(.caption)
                            }
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                }
            }
        }
        .onAppear {
            markerState.onClick = { marker in
                selectedMarker = marker
            }
            selectedMarker = markerState
        }
    }

    private func bubbleStyle() -> InfoBubbleStyle {
        InfoBubbleStyle(
            bubbleColor: colorScheme == .dark ? .black : .white,
            borderColor: colorScheme == .dark ? .gray : .black,
            contentPadding: 16,
            cornerRadius: 12,
            tailSize: 10
        )
    }
}
