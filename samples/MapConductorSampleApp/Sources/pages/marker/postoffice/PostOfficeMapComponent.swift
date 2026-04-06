import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import SwiftUI

struct PostOfficeMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onMapClick: (GeoPoint) -> Void
    let onInfoClick: ((PostOffice) -> Void)?

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
                content.markerTilingOptions = MarkerTilingOptions(iconScaleCallback: { _, zoom in
                    PostOfficeViewModel.iconScale(zoom: zoom)
                })
                content.markers = markers.map { Marker(state: $0) }
                if let marker = selectedMarker, let postOffice = marker.extra as? PostOffice {
                    content.infoBubbles = [
                        InfoBubble(marker: marker) {
                            PostOfficeInfoView(info: postOffice, onClick: onInfoClick)
                        }
                    ]
                }
                return content
            }()
        }
    }
}
