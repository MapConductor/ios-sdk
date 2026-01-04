import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI
import UIKit

struct AnimationMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider = MapProvider.initial()
    @StateObject private var viewModel = AnimationPageViewModel()

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = AnimationPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _googleState = StateObject(wrappedValue: GoogleMapViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                AnimationMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    allMarkers: viewModel.allMarkers,
                    onMapClick: { _ in }
                )

                // Message Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Animation list")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(spacing: 8) {
                        ForEach(viewModel.allMarkers) { marker in
                            Button(action: {
                                viewModel.onMarkerClick(marker)
                            }) {
                                Text(viewModel.getSpotName(markerId: marker.id))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                                    .background(Color.accentColor)
                                    .cornerRadius(8)
                            }
                        }
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
}
