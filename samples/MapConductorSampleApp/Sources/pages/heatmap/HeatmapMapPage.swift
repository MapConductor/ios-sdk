import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorHeatmap
import SwiftUI

struct HeatmapMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: HeatmapPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = HeatmapPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
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
                HeatmapMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    heatmap: viewModel.heatmap(for:),
                    points: viewModel.heatmapPoints,
                    onCameraMove: viewModel.onCameraMove(provider:camera:)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Heatmap")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Tokyo post offices heatmap via local tile server.")
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
        .onAppear {
            viewModel.setUseCameraZoomForTiles(isGoogleMaps: provider == .googleMaps)
        }
        .onChange(of: provider) { next in
            viewModel.setUseCameraZoomForTiles(isGoogleMaps: next == .googleMaps)
        }
    }
}
