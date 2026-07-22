import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import SwiftUI

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

    @StateObject private var mapboxState = MapboxViewState(
        cameraPosition: StoreDemoData.initCameraPosition
    )
    
    @StateObject private var arcGISState = ArcGISMapViewState(
        mapDesignType: ArcGISDesign.Streets,
        cameraPosition: StoreDemoData.initCameraPosition
    )
    
    @StateObject private var hereState = HereMapViewState(
        mapDesignType: HereMapDesign.NormalDay,
        cameraPosition: StoreDemoData.initCameraPosition
    )
    @StateObject private var tomTomState = TomTomMapViewState(
        mapDesignType: TomTomMapDesign.Standard,
        cameraPosition: StoreDemoData.initCameraPosition
    )

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            StoreMapComponent(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                arcGISState: arcGISState,
                hereState: hereState,
                tomTomState: tomTomState,
                markers: viewModel.markerList,
                selectedMarker: viewModel.selectedMarker,
                onDirectionButtonClick: { marker in
                    viewModel.openDirectionsInAppleMaps(for: marker)
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
