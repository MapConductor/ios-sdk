import GoogleMaps
import MapConductorForHERE
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import SwiftUI
import UIKit

struct PolylineMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState

    let polylineState: PolylineState
    let wayPointMarkers: [MarkerState]

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            arcGISState: arcGISState,
            hereState: hereState
        ) {
            { () -> MapViewContent in
            var content = MapViewContent()
            content.polylines = [Polyline(state: polylineState)]
            content.markers = wayPointMarkers.map { Marker(state: $0) }
                return content
            }()
        }
    }
}
