import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import SwiftUI
import UIKit

struct StoreMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onDirectionButtonClick: (MarkerState) -> Void
    let onMapClick: (GeoPoint) -> Void

    var body: some View {
        SampleMapView(
            provider: $provider,
            googleState: googleState,
            mapLibreState: mapLibreState,
            onMapClick: onMapClick,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
            }
        ) {
            var content = MapViewContent()
            content.markers = markers.map { Marker(state: $0) }
            if let marker = selectedMarker, let info = marker.extra as? StoreInfo {
                content.infoBubbles = [
                    InfoBubble(marker: marker) {
                        StoreInfoView(info: info) {
                            onDirectionButtonClick(marker)
                        }
                    }
                ]
            }
            return content
        }
    }
}
