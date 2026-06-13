import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorForArcGIS
import MapConductorForHERE
import SwiftUI
import UIKit

struct CircleMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState

    let circleState: CircleState
    let centerMarker: MarkerState
    let edgeMarker: MarkerState

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
            content.circles = [Circle(state: circleState)]
            content.markers = [
                Marker(state: centerMarker),
                Marker(state: edgeMarker)
            ]
                return content
            }()
        }
    }
}
