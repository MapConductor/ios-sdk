import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI

struct PolygonMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PolygonMapPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = PolygonMapPageViewModel()
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
                PolygonMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    polygonState: viewModel.polygonState,
                    polygonVertexMarkers: viewModel.polygonVertexMarkers
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Polygon Example")
                        .font(.headline)
                        .foregroundColor(.primary)

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
            viewModel.polygonState.fillColor = UIColor.blue.withAlphaComponent(viewModel.fillOpacity)
        }
        .onChange(of: viewModel.strokeWidth) { _ in
            viewModel.polygonState.strokeWidth = viewModel.strokeWidth
        }
    }
}
