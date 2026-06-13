import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI

struct StyledInfoBubblePage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var mapboxState = MapboxViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.OsmStandard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )
    
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 12
        )
    )

    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671)
    )

    private let style = InfoBubbleStyle(
        bubbleColor: Color.black.opacity(0.85),
        borderColor: Color.white,
        contentPadding: 10,
        cornerRadius: 10,
        tailSize: 10
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            SampleMapView(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                arcGISState: arcGISState,
                hereState: hereState,
                onMapClick: { point in markerState.position = point }
            ) {
                Marker(state: markerState)
                InfoBubble(marker: markerState, style: style) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Night Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Custom style bubble")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }
}
