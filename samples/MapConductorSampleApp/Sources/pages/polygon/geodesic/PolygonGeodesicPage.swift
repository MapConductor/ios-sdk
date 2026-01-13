import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

struct PolygonGeodesicPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PolygonGeodesicPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = PolygonGeodesicPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles,
                cameraPosition: vm.initCameraPosition
            )
        )
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard,
                cameraPosition: vm.initCameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                SampleMapView(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
            mapKitState: mapKitState,
                    sdkInitialize: {
                        GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                    }
                ) {
                    var content = MapViewContent()
                    let points: [GeoPointProtocol] = [
                        GeoPoint.fromLongLat(longitude: 23.66, latitude: 56.42),
                        GeoPoint.fromLongLat(longitude: 13.39, latitude: 2.95),
                        GeoPoint.fromLongLat(longitude: -87.82, latitude: 38.58),
                        GeoPoint.fromLongLat(longitude: 23.66, latitude: 56.42)
                    ]

                    let basePolygon = PolygonState(
                        points: points,
                        strokeColor: UIColor.yellow.withAlphaComponent(0.3),
                        strokeWidth: 3.0,
                        fillColor: UIColor.green.withAlphaComponent(0.5),
                        geodesic: false,
                        zIndex: 0,
                        onClick: viewModel.onPolygonClicked
                    )

                    let geodesicPolygon = PolygonState(
                        points: points,
                        strokeColor: UIColor.red.withAlphaComponent(0.3),
                        strokeWidth: 3.0,
                        fillColor: UIColor.blue.withAlphaComponent(0.5),
                        geodesic: true,
                        zIndex: 1,
                        onClick: viewModel.onPolygonClicked
                    )

                    content.polygons = [
                        Polygon(state: basePolygon),
                        Polygon(state: geodesicPolygon)
                    ]

                    if let marker = viewModel.markerState {
                        content.markers = [Marker(state: marker)]
                    }

                    return content
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Polygon Geodesic Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(
                        """
                        Tap on the polygons!
                        This example shows the ability of the polygon click detection.
                        Place a green marker if you tap on the green polygon,
                        and place a blue marker on the blue polygon if you tap on it.
                        """
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
