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
import MapConductorVectorTile
import SwiftUI

/// A map that works with the network off. See ``OfflineMapPageViewModel``.
struct OfflineMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: OfflineMapPageViewModel

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
        let vm = OfflineMapPageViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _provider = State(initialValue: MapProvider.initial())
        let camera = vm.initCameraPosition
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: camera))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(mapDesignType: MapLibreDesign.DemoTiles, cameraPosition: camera))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(mapDesignType: MapKitMapDesign.Standard, cameraPosition: camera))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: camera))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(mapDesignType: ArcGISDesign.OsmStandard, cameraPosition: camera))
        _hereState = StateObject(wrappedValue: HereMapViewState(mapDesignType: HereMapDesign.NormalDay, cameraPosition: camera))
        _tomTomState = StateObject(wrappedValue: TomTomMapViewState(mapDesignType: TomTomMapDesign.Standard, cameraPosition: camera))
        _mapTilerState = StateObject(wrappedValue: MapTilerViewState(mapDesignType: MapTilerDesign.Streets, cameraPosition: camera))
        _longdoState = StateObject(wrappedValue: LongdoViewState(mapDesignType: LongdoDesign.Normal, cameraPosition: camera))
        _openMobileMapsState = StateObject(wrappedValue: OpenMobileMapsViewState(mapDesignType: OpenMobileMapsDesign.openStreetMap, cameraPosition: camera))
        _mapplsState = StateObject(wrappedValue: MapplsViewState(mapDesignType: MapplsDesign.Default, cameraPosition: camera))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottom) {
                SampleMapView(
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
                    mapplsState: mapplsState
                ) {
                    { () -> MapViewContent in
                        var content = MapViewContent()
                        content.rasterLayers = ([viewModel.ground] + viewModel.labels)
                            .compactMap { $0 }
                            .map { RasterLayer(state: $0) }
                        if viewModel.selecting {
                            content.polygons = [Polygon(state: viewModel.mask)]
                            content.markers = [Marker(state: viewModel.swMarker), Marker(state: viewModel.neMarker)]
                        }
                        return content
                    }()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if viewModel.selecting {
                            Button(viewModel.progress == nil ? "Download" : "Downloading…") {
                                Task { await viewModel.download() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.progress != nil)
                            .accessibilityIdentifier("downloadButton")
                            Button("Cancel") { viewModel.cancelSelection() }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.progress != nil)
                                .accessibilityIdentifier("cancelSelectButton")
                        } else {
                            Button("Select area…") { viewModel.beginSelection(center: cameraCenter) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("selectAreaButton")
                            Button(viewModel.airplane ? "✈ Airplane mode ON" : "✈ Airplane mode") {
                                viewModel.airplane.toggle()
                            }
                            .buttonStyle(.bordered)
                            .tint(viewModel.airplane ? .orange : .accentColor)
                            .accessibilityIdentifier("airplaneToggle")
                            Button("Clear") { viewModel.clearPackage() }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.offlinePackage == nil)
                        }
                    }
                    .font(.caption)
                    Text(packageStatus)
                        .font(.caption)
                        .accessibilityIdentifier("offlineStatus")
                    Text("mode=\(viewModel.airplane ? "offline" : "online") fetches: \(viewModel.stats.map { "\($0)" } ?? "-")")
                        .font(.caption)
                        .accessibilityIdentifier("offlineFetches")
                    ForEach(viewModel.diagnostics, id: \.self) { Text($0).font(.caption2).foregroundColor(.orange) }
                    if let failure = viewModel.failure {
                        Text(failure).font(.caption2).foregroundColor(.red)
                    }
                }
                .padding(12)
                .frame(maxWidth: 520, alignment: .leading)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .padding(.bottom, 28)
            }
        }
        .task { await viewModel.loadStyle() }
        // The style is the map here: the backend's own basemap is blanked
        // wherever the backend can, and the MapLibre-based backends take the
        // style directly (and read the package through the local server).
        .task(id: mountKey) {
            if directSupport == nil { showProviderBasemap(currentState, visible: false) }
            viewModel.mount(direct: directSupport, preferredTileSize: preferredTileSize, key: mountKey)
        }
        .onDisappear {
            viewModel.unmount()
            showProviderBasemap(currentState, visible: true)
        }
    }

    private var packageStatus: String {
        if let progress = viewModel.progress { return "downloading: \(progress)" }
        if viewModel.selecting { return "drag SW/NE to choose the area, then Download" }
        guard let pkg = viewModel.offlinePackage else { return "no package: Select area…, then Download" }
        let m = pkg.manifest
        return "package: \(m.tiles) tiles, \(m.glyphs) glyph ranges, \(m.sprites) sprite files, z\(m.minZoom)-\(m.maxZoom), \(m.bytes / 1024) KB"
    }

    /// Everything a mount depends on, in one string; a change rebuilds the layer.
    private var mountKey: String {
        let pkg = viewModel.offlinePackage.map { "\($0.manifest.createdAt)" } ?? "none"
        return "\(provider)-\(viewModel.airplane ? "offline" : "online")-\(pkg)-\(directSupport != nil)-\(preferredTileSize ?? 0)-\(viewModel.diagnostics.isEmpty ? "s" : "m")"
    }

    /// Where the map is looking now; the area starts centred on it.
    private var cameraCenter: GeoPoint {
        let position = (currentState as? (any MapViewStateProtocol))?.cameraPosition.position
        return position.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
            ?? GeoPoint(latitude: viewModel.initCameraPosition.position.latitude, longitude: viewModel.initCameraPosition.position.longitude)
    }

    private var directSupport: VectorStyleSupport? { currentRegistry.get(VectorStyleSupportKey.self) }
    private var preferredTileSize: Int? { currentRegistry.get(RasterTilePreferenceKey.self)?.preferredTileSize }

    private var currentState: AnyObject {
        switch provider {
        case .googleMaps: return googleState
        case .mapLibre: return mapLibreState
        case .mapKit: return mapKitState
        case .mapbox: return mapboxState
        case .arcGIS, .arcGIS2D: return arcGISState
        case .here: return hereState
        case .tomTom: return tomTomState
        case .mapTiler: return mapTilerState
        case .longdo: return longdoState
        case .openMobileMaps: return openMobileMapsState
        case .mappls: return mapplsState
        }
    }

    private var currentRegistry: MutableMapServiceRegistry {
        (currentState as? (any MapViewStateProtocol))?.serviceRegistry ?? MutableMapServiceRegistry()
    }
}
