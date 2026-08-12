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
import MapConductorMarkerClustering
import SwiftUI

struct PostOfficeClusterMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: PostOfficeClusterPageViewModel

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
        let image = Self.loadPngImage(named: "postoffice") ?? UIImage()
        let postOfficeIcon = ImageIcon(image: image, scale: 0.3)
        let vm = PostOfficeClusterPageViewModel(postOfficeIcon: postOfficeIcon)
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
                PostOfficeClusterMapComponent(
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
                    debugHullPolygons: viewModel.debugHullPolygons,
                    onMapClick: { _ in
                        viewModel.clearSelection()
                    },
                    onInfoClick: { office in
                        focus(on: office)
                    },
                    onClusterClick: { cluster in
                        zoomToCluster(cluster)
                    }
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Controls")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Toggle(isOn: $viewModel.debugHullPolygons) {
                        Text("debug")
                            .font(.subheadline)
                    }
                }
                .padding(16)
                .background(Color(UIColor.systemBackground).opacity(0.95))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.leading, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                if viewModel.isDataLoading {
                    LoadingOverlay(
                        title: "Loading Post Offices",
                        message: "Generating markers..."
                    )
                }
            }
        }
        .onAppear {
            viewModel.loadPostOffices()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                refreshCurrentCamera()
            }
        }
        .onChange(of: provider) { _ in
            refreshCurrentCamera()
        }
    }

    /// 現在のプロバイダの state。カメラ操作をプロバイダ非依存に書くための束ね。
    private var activeState: any MapViewStateProtocol {
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

    /// クラスターをクリックしたら、クラスター内マーカーの重心へズームインする
    /// （android の MarkerClusterMapPageViewModel.onClusterClicked / react の
    /// useClusterClick と同一仕様: zoom+2、上限 18、600ms）。
    private func zoomToCluster(_ cluster: MarkerCluster) {
        let byId = Dictionary(viewModel.markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let positions = cluster.markerIds.compactMap { byId[$0]?.position }
        guard !positions.isEmpty else { return }
        let lat = positions.map(\.latitude).reduce(0, +) / Double(positions.count)
        let lng = positions.map(\.longitude).reduce(0, +) / Double(positions.count)
        let state = activeState
        let currentZoom = state.cameraPosition.zoom
        state.moveCameraTo(
            cameraPosition: MapCameraPosition(
                position: GeoPoint.fromLatLong(latitude: lat, longitude: lng),
                zoom: min(currentZoom + 2.0, 18.0),
                bearing: 0.0,
                tilt: 0.0,
                paddings: nil
            ),
            durationMillis: 600
        )
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
        case .arcGIS, .arcGIS2D:
            arcGISState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .here:
            hereState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .tomTom:
            tomTomState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .mapTiler:
            mapTilerState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .longdo:
            longdoState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .openMobileMaps:
            openMobileMapsState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        case .mappls:
            mapplsState.moveCameraTo(cameraPosition: camera, durationMillis: 2000)
        }
    }

    private func refreshCurrentCamera() {
        switch provider {
        case .googleMaps:
            let current = googleState.cameraPosition
            let nudged = current.copy(zoom: current.zoom + 0.0001)
            googleState.moveCameraTo(cameraPosition: nudged, durationMillis: 0)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                googleState.moveCameraTo(cameraPosition: current, durationMillis: 0)
            }
        case .mapLibre:
            mapLibreState.moveCameraTo(cameraPosition: mapLibreState.cameraPosition, durationMillis: 0)
        case .mapKit:
            mapKitState.moveCameraTo(cameraPosition: mapKitState.cameraPosition, durationMillis: 0)
        case .mapbox:
            mapboxState.moveCameraTo(cameraPosition: mapboxState.cameraPosition, durationMillis: 0)
        case .arcGIS, .arcGIS2D:
            arcGISState.moveCameraTo(cameraPosition: arcGISState.cameraPosition, durationMillis: 0)
        case .here:
            hereState.moveCameraTo(cameraPosition: hereState.cameraPosition, durationMillis: 0)
        case .tomTom:
            tomTomState.moveCameraTo(cameraPosition: tomTomState.cameraPosition, durationMillis: 0)
        case .mapTiler:
            mapTilerState.moveCameraTo(cameraPosition: mapTilerState.cameraPosition, durationMillis: 0)
        case .longdo:
            longdoState.moveCameraTo(cameraPosition: longdoState.cameraPosition, durationMillis: 0)
        case .openMobileMaps:
            openMobileMapsState.moveCameraTo(cameraPosition: openMobileMapsState.cameraPosition, durationMillis: 0)
        case .mappls:
            mapplsState.moveCameraTo(cameraPosition: mapplsState.cameraPosition, durationMillis: 0)
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

private struct LoadingOverlay: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
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
