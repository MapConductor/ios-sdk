import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import SwiftUI
import UIKit

struct PolylineClickMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState

    let polylineState: PolylineState
    let markers: [MarkerState]

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            mapKitState: mapKitState,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
            }
        ) {
            var content = MapViewContent()
            content.polylines = [
                Polyline(state: polylineState),
                Polyline(state: polylineState.copy(
                    id: "\(polylineState.id)-straight",
                    strokeColor: UIColor.blue,
                    geodesic: false
                ))
            ]
            content.markers = markers.map { Marker(state: $0) }
            return content
        }
    }
}
