import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

struct StoreMapPage: View {
    let onToggleSidebar: () -> Void

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
    }

    @State private var provider: MapProvider = MapProvider.initial()
    @StateObject private var viewModel = StoreMapPageViewModel()

    @StateObject private var googleState = GoogleMapViewState(
        cameraPosition: StoreDemoData.initCameraPosition
    )

    @StateObject private var mapLibreState = MapLibreViewState(
        mapDesignType: MapLibreDesign.DemoTiles,
        cameraPosition: StoreDemoData.initCameraPosition
    )

    @StateObject private var mapKitState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: StoreDemoData.initCameraPosition
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            StoreMapComponent(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                markers: viewModel.markerList,
                selectedMarker: viewModel.selectedMarker,
                onDirectionButtonClick: { marker in
                    if let url = viewModel.directionURL(for: marker) {
                        UIApplication.shared.open(url)
                    }
                },
                onMapClick: viewModel.onMapClick
            )
        }
        .onChange(of: provider) { newProvider in
            viewModel.onMapViewChanged(provider: newProvider)
        }
        .onAppear {
            viewModel.onMapViewChanged(provider: provider)
        }
    }
}
