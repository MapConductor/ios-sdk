import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

struct MapDesignMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider = MapProvider.initial()
    @StateObject private var viewModel = MapDesignPageViewModel()

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = MapDesignPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _googleState = StateObject(wrappedValue: GoogleMapViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: vm.initCameraPosition
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                MapDesignMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState
                )

                // Message Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select Map Design...")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Menu {
                        ForEach(viewModel.mapDesignOptions.indices, id: \.self) { index in
                            let option = viewModel.mapDesignOptions[index]
                            Button(option.label) {
                                selectMapDesign(option)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Map design")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
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
        .onChange(of: provider) { newProvider in
            viewModel.onMapViewChanged(provider: newProvider)
        }
        .onAppear {
            viewModel.onMapViewChanged(provider: provider)
        }
    }

    private func selectMapDesign(_ option: MapDesignOption) {
        switch provider {
        case .googleMaps:
            if let design = option.design as? GoogleMapDesignType {
                googleState.mapDesignType = design
            }
        case .mapLibre:
            if let design = option.design as? MapLibreDesign {
                mapLibreState.mapDesignType = design
            }
        case .mapKit:
            if let design = option.design as? MapKitMapDesignType {
                mapKitState.mapDesignType = design
            }
        }
    }
}
