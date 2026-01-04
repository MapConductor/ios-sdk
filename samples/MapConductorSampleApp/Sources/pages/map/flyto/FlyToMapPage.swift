import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

struct FlyToMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: FlyToPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = FlyToPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles,
                cameraPosition: vm.initCameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                FlyToMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    polylines: viewModel.polylines,
                    markers: viewModel.markers
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Fly To Controls")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Toggle(isOn: $viewModel.geodesic) {
                        Text("geodesic")
                            .font(.subheadline)
                    }

                    HStack(spacing: 8) {
                        Button("Sydney") {
                            viewModel.flyToSydney(state: activeState)
                        }
                        .frame(maxWidth: .infinity)

                        Button("Honolulu") {
                            viewModel.flyToHonolulu(state: activeState)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 8) {
                        Button("Tokyo") {
                            viewModel.flyToTokyo(state: activeState)
                        }
                        .frame(maxWidth: .infinity)

                        Button("London") {
                            viewModel.flyToLondon(state: activeState)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 8) {
                        Button("New York") {
                            viewModel.flyToNewYork(state: activeState)
                        }
                        .frame(maxWidth: .infinity)
                    }
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

    private var activeState: MapViewStateProtocol {
        switch provider {
        case .googleMaps:
            return googleState
        case .mapLibre:
            return mapLibreState
        }
    }
}
