import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI
import UIKit

struct AnimationMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    let allMarkers: [MarkerState]
    let onMapClick: (GeoPoint) -> Void

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            mapboxState: mapboxState,
            onMapClick: onMapClick,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                initializeMapbox(accessToken: SampleConfig.mapboxAccessToken)
            }
        ) {
            { () -> MapViewContent in
            var content = MapViewContent()
            content.markers = allMarkers.map { Marker(state: $0) }
                return content
            }()
        }
    }
}
