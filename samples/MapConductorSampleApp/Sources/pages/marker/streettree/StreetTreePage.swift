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
import MapConductorForOpenMobileMaps
import MapConductorForMappls
import SwiftUI

struct StreetTreePage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: StreetTreeViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState
    @StateObject private var mapTilerState: MapTilerViewState
    @StateObject private var longdoState: LongdoViewState
    @StateObject private var openMobileMapsState: OpenMobileMapsViewState
    @StateObject private var mapplsState: MapplsViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = StreetTreeViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        // A basemap stripped down to what a tree map needs: land, water, the
        // major roads and the place names, with the finer streets appearing
        // from zoom 13. The default style draws 51 transportation line layers,
        // and at this density they compete with the trees for every pixel.
        //
        // MapLibre only, by construction: the design type is provider-specific
        // and this one carries a style URL. On any other provider the page runs
        // on that provider's own basemap.
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: Self.treeStyle(),
            cameraPosition: vm.initCameraPosition
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(
            cameraPosition: vm.initCameraPosition
        ))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(
            mapDesignType: ArcGISDesign.OsmStandard,
            cameraPosition: vm.initCameraPosition
        ))
        _hereState = StateObject(wrappedValue: HereMapViewState(
            mapDesignType: HereMapDesign.NormalDay,
            cameraPosition: vm.initCameraPosition
        ))
        _tomTomState = StateObject(wrappedValue: TomTomMapViewState(
            mapDesignType: TomTomMapDesign.Standard,
            cameraPosition: vm.initCameraPosition
        ))
        _mapTilerState = StateObject(wrappedValue: MapTilerViewState(
            mapDesignType: MapTilerDesign.Streets,
            cameraPosition: vm.initCameraPosition
        ))
        _longdoState = StateObject(wrappedValue: LongdoViewState(
            mapDesignType: LongdoDesign.Normal,
            cameraPosition: vm.initCameraPosition
        ))
        _openMobileMapsState = StateObject(wrappedValue: OpenMobileMapsViewState(
            mapDesignType: OpenMobileMapsDesign.openStreetMap,
            cameraPosition: vm.initCameraPosition
        ))
        _mapplsState = StateObject(wrappedValue: MapplsViewState(
            mapDesignType: MapplsDesign.Default,
            cameraPosition: vm.initCameraPosition
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .center) {
                StreetTreeMapComponent(
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
                    openMobileMapsState: openMobileMapsState,
                    mapplsState: mapplsState,
                    markers: viewModel.markers,
                    selectedMarker: viewModel.selectedMarker,
                    markerTiling: viewModel.markerTiling,
                    onMapClick: { _ in viewModel.clearSelection() }
                )

                if viewModel.isDataLoading {
                    StreetTreeLoadingOverlay(message: "Loading 144,183 street trees...")
                }
            }
        }
        .onAppear {
            viewModel.loadTrees()
        }
    }

    /// The stripped-down basemap, read from the app bundle.
    ///
    /// A file URL rather than a remote one: the style is part of the sample, and
    /// its sources still point at the same tile server the other pages use.
    private static func treeStyle() -> MapLibreDesign {
        guard let url = Bundle.main.url(forResource: "street-tree-style", withExtension: "json") else {
            return MapLibreDesign.OsmBrightJa
        }
        return MapLibreDesign(id: "street-tree", styleJsonURL: url.absoluteString)
    }
}

private struct StreetTreeLoadingOverlay: View {
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
