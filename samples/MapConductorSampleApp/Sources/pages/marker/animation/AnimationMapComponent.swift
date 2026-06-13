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

struct AnimationMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState
    @ObservedObject var arcGISState: ArcGISMapViewState
    @ObservedObject var hereState: HereMapViewState

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
