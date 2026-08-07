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

struct VisibleRegionPage: View {
    let onToggleSidebar: () -> Void

    @State private var provider: MapProvider
    @StateObject private var viewModel = VisibleRegionViewModel()

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
        let initCamera = MapCameraPosition(
            position: GeoPoint(latitude: 35.6762, longitude: 139.6503),
            zoom: 10.0
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
        _tomTomState = StateObject(wrappedValue: TomTomMapViewState(
            mapDesignType: TomTomMapDesign.Standard,
            cameraPosition: initCamera
        ))
        _mapTilerState = StateObject(wrappedValue: MapTilerViewState(
            mapDesignType: MapTilerDesign.Streets,
            cameraPosition: initCamera
        ))
        _longdoState = StateObject(wrappedValue: LongdoViewState(
            mapDesignType: LongdoDesign.Normal,
            cameraPosition: initCamera
        ))
    }

    var body: some View {
        DemoMapPageScaffold(provider: $provider, onToggleSidebar: onToggleSidebar) {
            VisibleRegionMapComponent(
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
                onCameraChanged: { camera in
                    viewModel.onCameraChanged(camera)
                }
            )
        }
    }
}
