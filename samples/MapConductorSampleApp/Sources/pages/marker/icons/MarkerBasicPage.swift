import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI

struct MarkerBasicPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider

    @StateObject private var googleState: GoogleMapViewState
    @StateObject private var mapLibreState: MapLibreViewState
    @StateObject private var mapKitState: MapKitViewState
    @StateObject private var mapboxState: MapboxViewState
    @StateObject private var arcGISState: ArcGISMapViewState
    @StateObject private var hereState: HereMapViewState

    init(onToggleSidebar: @escaping () -> Void = {}) {
        self.onToggleSidebar = onToggleSidebar
        let initCamera = MapCameraPosition(
            position: GeoPoint(latitude: 0.014, longitude: 0.008),
            zoom: 15.0
        )
        _provider = State(initialValue: MapProvider.initial())
        _googleState = StateObject(wrappedValue: GoogleMapViewState(cameraPosition: initCamera))
        _mapLibreState = StateObject(wrappedValue: MapLibreViewState(
            mapDesignType: MapLibreDesign.DemoTiles,
            cameraPosition: initCamera
        ))
        _mapKitState = StateObject(wrappedValue: MapKitViewState(
            mapDesignType: MapKitMapDesign.Standard,
            cameraPosition: initCamera
        ))
        _mapboxState = StateObject(wrappedValue: MapboxViewState(
            cameraPosition: initCamera
        ))
        _arcGISState = StateObject(wrappedValue: ArcGISMapViewState(
            mapDesignType: ArcGISDesign.OsmStandard,
            cameraPosition: initCamera
        ))
        _hereState = StateObject(wrappedValue: HereMapViewState(
            mapDesignType: HereMapDesign.NormalDay,
            cameraPosition: initCamera
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            MarkerBasicMapComponent(
                provider: $provider,
                googleState: googleState,
                mapLibreState: mapLibreState,
                mapKitState: mapKitState,
                mapboxState: mapboxState,
                arcGISState: arcGISState,
                hereState: hereState
            )
        }
    }
}
