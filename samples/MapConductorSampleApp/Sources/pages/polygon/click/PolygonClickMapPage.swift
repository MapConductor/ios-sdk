import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

struct PolygonClickMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PolygonClickPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = PolygonClickPageViewModel()
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
                    onMapClick: viewModel.onMapClicked,
                    sdkInitialize: {
                        GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                    }
                ) {
                    var content = MapViewContent()
                    content.polygons = california.map { points in
                        Polygon(
                            points: points,
                            strokeColor: UIColor.red.withAlphaComponent(0.7),
                            strokeWidth: 3.0,
                            fillColor: UIColor.blue.withAlphaComponent(0.4),
                            onClick: viewModel.onPolygonClicked
                        )
                    }

                    if let marker = viewModel.markerState {
                        content.markers = [Marker(state: marker)]
                        content.infoBubbles = [
                            InfoBubble(marker: marker) {
                                Text(viewModel.message)
                                    .foregroundColor(.black)
                            }
                        ]
                    }

                    return content
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Polygon Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tap inside & outside the polygon!")
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
