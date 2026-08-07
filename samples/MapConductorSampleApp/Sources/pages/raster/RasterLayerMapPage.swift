import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import MapConductorForLongdo
import SwiftUI

struct RasterLayerMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: RasterLayerPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState
    @StateObject private var mapTilerState: MapTilerViewState
    @StateObject private var longdoState: LongdoViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = RasterLayerPageViewModel()
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
        _mapTilerState = StateObject(
            wrappedValue: MapTilerViewState(
                mapDesignType: MapTilerDesign.Streets,
                cameraPosition: vm.initCameraPosition
            )
        )
        _longdoState = StateObject(
            wrappedValue: LongdoViewState(
                mapDesignType: LongdoDesign.Normal,
                cameraPosition: vm.initCameraPosition
            )
        )
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                RasterLayerMapComponent(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    tomTomState: tomTomState,
                    mapTilerState: mapTilerState,
                    longdoState: longdoState,
                    rasterLayerState: viewModel.rasterLayerState
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Raster Layer Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Menu {
                        ForEach(viewModel.availableLayers) { layer in
                            Button {
                                viewModel.selectLayer(layer)
                            } label: {
                                if layer.id == viewModel.selectedLayer.id {
                                    Label(layer.displayName, systemImage: "checkmark")
                                } else {
                                    Text(layer.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("GSI layer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(viewModel.selectedLayer.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if provider == .tomTom {
                            Text("Opacity: not available for TomTom")
                        } else {
                            Text("Opacity: \(String(format: "%.1f", viewModel.opacity))")
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.opacity },
                                set: { viewModel.setOpacity($0) }
                            ),
                            in: 0.0...1.0
                        )
                        .disabled(provider == .tomTom)
                    }
                    .font(.subheadline)
                    .foregroundColor(.primary)
                }
                .padding(16)
                .frame(maxWidth: 360)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
