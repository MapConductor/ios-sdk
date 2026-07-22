import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import SwiftUI

struct FitBoundsMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: FitBoundsPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = FitBoundsPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(
            wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition)
        )
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
        _mapboxState = StateObject(
            wrappedValue: MapboxViewState(
                cameraPosition: vm.initCameraPosition
            )
        )
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard,
                cameraPosition: vm.initCameraPosition
            )
        )
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay,
                cameraPosition: vm.initCameraPosition
            )
        )
        _tomTomState = StateObject(
            wrappedValue: TomTomMapViewState(
                mapDesignType: TomTomMapDesign.Standard,
                cameraPosition: vm.initCameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                FitBoundsMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    tomTomState: tomTomState,
                    marker: viewModel.marker,
                    boundsPolygon: viewModel.boundsPolygon,
                )
                .onAppear { viewModel.setActiveState(activeState) }
                .onChange(of: provider) { _ in viewModel.setActiveState(activeState) }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Fit Bounds")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("マーカーをドラッグして範囲を指定し、ドロップすると fitBounds で地図が移動します。")
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

    private var activeState: any MapViewStateProtocol {
        switch provider {
        case .googleMaps: return googleState
        case .mapLibre:   return mapLibreState
        case .mapKit:     return mapKitState
        case .mapbox:     return mapboxState
        case .arcGIS:     return arcGISState
        case .here:       return hereState
        case .tomTom:       return tomTomState
        }
    }
}
