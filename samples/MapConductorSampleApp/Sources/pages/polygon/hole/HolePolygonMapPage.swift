import MapConductorCore
import MapConductorForArcGIS
import MapConductorForGoogleMaps
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapKit
import MapConductorForMapLibre
import MapConductorForMapbox
import SwiftUI

struct HolePolygonMapPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel: HolePolygonMapPageViewModel

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState
    @StateObject private var tomTomState: TomTomMapViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let vm = HolePolygonMapPageViewModel()
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
        _mapboxState = StateObject(wrappedValue: MapboxViewState(cameraPosition: vm.initCameraPosition))
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
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            ZStack(alignment: .bottomLeading) {
                SampleMapView(
                    provider: $provider,
                    googleState: googleState,
                    mapLibreState: mapLibreState,
                    mapKitState: mapKitState,
                    mapboxState: mapboxState,
                    arcGISState: arcGISState,
                    hereState: hereState,
                    tomTomState: tomTomState
                ) {
                    { () -> MapViewContent in
                        var content = MapViewContent()
                        content.polygons = [Polygon(state: viewModel.polygonState)]
                        content.markers = viewModel.holeVertexMarkers.map { Marker(state: $0) }
                        return content
                    }()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hole Polygon Example")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(
                        """
                        A world-covering polygon with two triangular holes near Sapporo.
                        Drag hole vertex markers to reshape the holes.
                        """
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
