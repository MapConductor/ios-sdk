import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForLongdo
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapTiler
import MapConductorForMapbox
import MapConductorForMappls
import MapConductorForOpenMobileMaps
import MapConductorForTomTom
import SwiftUI

/**
 Draws a MapLibre vector style on whichever backend is selected.

 The point of the page is the provider switcher at the top: Google Maps, MapKit,
 HERE, ArcGIS and the rest cannot render a vector style, yet all of them show
 this one — because what they are handed is an ordinary raster layer whose tiles
 were rendered on the device.
 */
struct VectorTileMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @State private var asBasemap = false
    @StateObject private var viewModel: VectorTilePageViewModel

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
        let vm = VectorTilePageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(
            wrappedValue: GoogleMapViewState(cameraPosition: vm.initCameraPosition))
        _mapLibreState = StateObject(
            wrappedValue: MapLibreViewState(
                mapDesignType: MapLibreDesign.DemoTiles, cameraPosition: vm.initCameraPosition))
        _mapKitState = StateObject(
            wrappedValue: MapKitViewState(
                mapDesignType: MapKitMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _mapboxState = StateObject(
            wrappedValue: MapboxViewState(cameraPosition: vm.initCameraPosition))
        _arcGISState = StateObject(
            wrappedValue: ArcGISMapViewState(
                mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: vm.initCameraPosition))
        _hereState = StateObject(
            wrappedValue: HereMapViewState(
                mapDesignType: HereMapDesign.NormalDay, cameraPosition: vm.initCameraPosition))
        _tomTomState = StateObject(
            wrappedValue: TomTomMapViewState(
                mapDesignType: TomTomMapDesign.Standard, cameraPosition: vm.initCameraPosition))
        _mapTilerState = StateObject(
            wrappedValue: MapTilerViewState(
                mapDesignType: MapTilerDesign.Streets, cameraPosition: vm.initCameraPosition))
        _longdoState = StateObject(
            wrappedValue: LongdoViewState(
                mapDesignType: LongdoDesign.Normal, cameraPosition: vm.initCameraPosition))
        _openMobileMapsState = StateObject(
            wrappedValue: OpenMobileMapsViewState(
                mapDesignType: OpenMobileMapsDesign.openStreetMap,
                cameraPosition: vm.initCameraPosition))
        _mapplsState = StateObject(
            wrappedValue: MapplsViewState(
                mapDesignType: MapplsDesign.Default, cameraPosition: vm.initCameraPosition))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                VectorTileMapComponent(
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
                    ground: viewModel.ground,
                    labels: viewModel.labels
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Vector Tile Layer")
                        .font(.headline)
                        .foregroundColor(.primary)

                    // Read by the UI test on the iPad: it is how a run says
                    // whether the layer mounted, rather than a screenshot
                    // somebody has to squint at.
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("vectorTileStatus")

                    Toggle("As basemap", isOn: $asBasemap)
                        .font(.caption)
                        .accessibilityIdentifier("asBasemapToggle")

                    // Undrawn layer types and unusable sources are worth
                    // showing: the failure mode that matters is a blank tile
                    // with no explanation.
                    ForEach(viewModel.diagnostics, id: \.self) { message in
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if let failure = viewModel.failure {
                        Text("style failed: \(failure)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .padding(16)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }
        }
        .task { await viewModel.load() }
        // Re-runs whenever the answer changes, which covers both the first one
        // (a provider registers as it binds, after this page appears) and a
        // switch to a backend that wants a different size.
        .task(id: preferredTileSize) { await viewModel.use(preferredTileSize: preferredTileSize) }
        .onChange(of: asBasemap) { _ in showBasemap(!asBasemap) }
        .onChange(of: provider) { _ in showBasemap(!asBasemap) }
        .onDisappear {
            viewModel.dispose()
            showBasemap(true)
        }
    }

    /**
     Blanks the selected backend's own basemap, or restores it.

     Which design means "draw nothing" is provider-specific, and only some
     providers have one (Google, ArcGIS; MapLibre says it with an empty
     style). Where there is none the opaque tiles cover it anyway -- the
     difference is whether the device also fetches a basemap nobody sees.
     */
    private func showBasemap(_ visible: Bool) {
        switch provider {
        case .mapLibre:
            if visible {
                mapLibreState.mapDesignType = MapLibreDesign.DemoTiles
            } else if let blank = Bundle.main.url(forResource: "blank-style", withExtension: "json") {
                mapLibreState.mapDesignType = MapLibreDesign(id: "blank", styleJsonURL: blank.absoluteString)
            }
        case .googleMaps:
            googleState.mapDesignType = visible ? GoogleMapDesign.Normal : GoogleMapDesign.None
        case .arcGIS, .arcGIS2D:
            arcGISState.mapDesignType = visible ? ArcGISDesign.OsmStandard : ArcGISDesign.None
        case .mapbox:
            mapboxState.mapDesignType = visible ? MapboxMapDesign.Standard : MapboxMapDesign.None
        case .tomTom:
            tomTomState.mapDesignType = visible ? TomTomMapDesign.Standard : TomTomMapDesign.None
        case .mapTiler:
            mapTilerState.mapDesignType = visible ? MapTilerDesign.Streets : MapTilerDesign.None
        case .longdo:
            longdoState.mapDesignType = visible ? LongdoDesign.Normal : LongdoDesign.None
        case .openMobileMaps:
            openMobileMapsState.mapDesignType =
                visible ? OpenMobileMapsDesign.openStreetMap : OpenMobileMapsDesign.none
        // MapKit, HERE and Mappls have no design that draws nothing; the
        // opaque tiles cover their basemap, which is still fetched. HERE's
        // only route is a custom style exported from its Style Editor.
        case .mapKit, .here, .mappls:
            break
        }
    }

    /**
     The tile size the selected backend says it can handle, if it says.

     Providers declare this through the map-scoped service registry; the same
     declaration is read by android's `VectorTileLayer` and react's. Nothing
     declared means no preference, and the supplying side's own default stands.
     */
    private var preferredTileSize: Int? {
        let registry: MutableMapServiceRegistry
        switch provider {
        case .googleMaps: registry = googleState.serviceRegistry
        case .mapLibre: registry = mapLibreState.serviceRegistry
        case .mapKit: registry = mapKitState.serviceRegistry
        case .mapbox: registry = mapboxState.serviceRegistry
        case .arcGIS, .arcGIS2D: registry = arcGISState.serviceRegistry
        case .here: registry = hereState.serviceRegistry
        case .tomTom: registry = tomTomState.serviceRegistry
        case .mapTiler: registry = mapTilerState.serviceRegistry
        case .longdo: registry = longdoState.serviceRegistry
        case .openMobileMaps: registry = openMobileMapsState.serviceRegistry
        case .mappls: registry = mapplsState.serviceRegistry
        }
        return registry.get(RasterTilePreferenceKey.self)?.preferredTileSize
    }

    /// One line a test can assert on: whether the layers mounted, how many
    /// credits the style asked for, and which glyph generation is showing.
    private var status: String {
        if viewModel.failure != nil { return "failed" }
        guard viewModel.ground != nil, viewModel.labels != nil else { return "loading" }
        // `tile=` is how a run says the backend's declared size was honoured;
        // `mode=` says where the drawing actually happened, because a GPU path
        // that falls back on every tile looks exactly like a working one from
        // the outside and costs several times as much.
        return "mounted credits=\(viewModel.attributions.count) tile=\(viewModel.tileSize) "
            + "mode=\(viewModel.renderMode) generation=\(viewModel.generation) \(viewModel.observed)"
    }
}
