import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI

struct CircleMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: CirclePageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = CirclePageViewModel()
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
                CircleMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    circleState: viewModel.circleState,
                    centerMarker: viewModel.centerMarker,
                    edgeMarker: viewModel.edgeMarker
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Circle Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(viewModel.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "Fill Opacity: %.1f", viewModel.fillOpacity))
                            .font(.subheadline)
                        Slider(value: $viewModel.fillOpacity, in: 0.0...1.0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "Stroke Width: %.1f", viewModel.strokeWidth))
                            .font(.subheadline)
                        Slider(value: $viewModel.strokeWidth, in: 0.0...10.0)
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
        .onChange(of: viewModel.fillOpacity) { _ in
            viewModel.updateCircleFillColor()
        }
        .onChange(of: viewModel.strokeWidth) { _ in
            viewModel.updateCircleStrokeWidth()
        }
    }
}
