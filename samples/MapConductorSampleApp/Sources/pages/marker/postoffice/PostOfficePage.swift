import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI

struct PostOfficePage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PostOfficeViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let image = Self.loadPngImage(named: "postoffice") ?? UIImage()
        let postOfficeIcon = ImageIcon(image: image, scale: 0.5)
        let vm = PostOfficeViewModel(postOfficeIcon: postOfficeIcon)
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: vm.initCameraPosition
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .center) {
                PostOfficeMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    markers: viewModel.markers,
                    selectedMarker: viewModel.selectedMarker,
                    onMapClick: { _ in viewModel.clearSelection() },
                    onInfoClick: { office in
                        focus(on: office)
                    }
                )

                if viewModel.isDataLoading {
                    PostOfficeLoadingOverlay(message: "Loading Post Offices...")
                }
            }
        }
        .onAppear {
            viewModel.loadPostOffices()
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
        case .mapKit:
            mapKitState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .mapbox:
            mapboxState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        }
    }

    private static func loadPngImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}

private struct PostOfficeLoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
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
