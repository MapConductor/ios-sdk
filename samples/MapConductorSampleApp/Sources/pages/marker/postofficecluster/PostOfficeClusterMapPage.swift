import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

struct PostOfficeClusterMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PostOfficeClusterPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = PostOfficeClusterPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .center) {
                PostOfficeClusterMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    markers: viewModel.markers,
                    selectedMarker: viewModel.selectedMarker,
                    onMapClick: { _ in
                        viewModel.clearSelection()
                    },
                    onInfoClick: { office in
                        focus(on: office)
                    }
                )

                if viewModel.isDataLoading {
                    LoadingOverlay(
                        title: "Loading Post Offices",
                        message: "Generating markers..."
                    )
                }
            }
        }
        .onAppear {
            viewModel.loadPostOffices()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                refreshCurrentCamera()
            }
        }
        .onChange(of: provider) { _ in
            refreshCurrentCamera()
        }
    }

    private func focus(on office: PostOffice) {
        let camera = MapCameraPosition(
            position: office.position,
            zoom: 18.0,
            bearing: 0.0,
            tilt: 30.0,
            paddings: nil
        )
        switch provider {
        case .googleMaps:
            googleState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .mapLibre:
            mapLibreState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        }
    }

    private func refreshCurrentCamera() {
        switch provider {
        case .googleMaps:
            let current = googleState.cameraPosition
            let nudged = current.copy(zoom: current.zoom + 0.0001)
            googleState.moveCameraTo(cameraPosition: nudged, durationMillis: 0)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                googleState.moveCameraTo(cameraPosition: current, durationMillis: 0)
            }
        case .mapLibre:
            mapLibreState.moveCameraTo(cameraPosition: mapLibreState.cameraPosition, durationMillis: 0)
        }
    }
}

private struct LoadingOverlay: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
