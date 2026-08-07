import GoogleMaps
import MapConductorForLongdo
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import MapConductorForTomTom
import MapConductorForMapTiler
import SwiftUI
import UIKit

struct AnimationMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState
    @ObservedObject var tomTomState: TomTomMapViewState
    @ObservedObject var mapTilerState: MapTilerViewState
    @ObservedObject var longdoState: LongdoViewState

    let allMarkers: [MarkerState]
    let onMapClick: (GeoPoint) -> Void

    var body: some View {
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
            onMapClick: onMapClick
        ) {
            { () -> MapViewContent in
            var content = MapViewContent()
            content.markers = allMarkers.map { Marker(state: $0) }
                return content
            }()
        }
    }
}
