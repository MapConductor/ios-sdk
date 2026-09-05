import GoogleMaps
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

struct StreetTreeMapComponent: View {
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
    @ObservedObject var openMobileMapsState: OpenMobileMapsViewState
    @ObservedObject var mapplsState: MapplsViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let markerTiling: MarkerTilingOptions
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
            openMobileMapsState: openMobileMapsState,
            mapplsState: mapplsState,
            onMapClick: onMapClick
        ) {
            { () -> MapViewContent in
                var content = MapViewContent()
                content.markerTilingOptions = markerTiling
                content.markers = markers.map { Marker(state: $0) }
                if let marker = selectedMarker, let tree = marker.extra as? StreetTree {
                    content.infoBubbles = [
                        InfoBubble(marker: marker) {
                            StreetTreeInfoView(tree: tree)
                        }
                    ]
                }
                return content
            }()
        }
    }
}
