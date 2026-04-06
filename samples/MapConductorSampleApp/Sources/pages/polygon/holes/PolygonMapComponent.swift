import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI
import UIKit

struct PolygonMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    let polygonState: PolygonState
    let polygonVertexMarkers: [MarkerState]

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                initializeMapbox(accessToken: SampleConfig.mapboxAccessToken)
            }
        ) {
            { () -> MapViewContent in
                var content = MapViewContent()
                content.polygons = [Polygon(state: polygonState)]
                content.markers = polygonVertexMarkers.map { Marker(state: $0) }
                return content
            }()
        }
    }
}
