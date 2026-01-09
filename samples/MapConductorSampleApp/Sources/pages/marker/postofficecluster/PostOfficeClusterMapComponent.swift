import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorMarkerClustering
import MapLibre
import SwiftUI
import UIKit

struct PostOfficeClusterMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onMapClick: (GeoPoint) -> Void
    let onInfoClick: ((PostOffice) -> Void)?

    @State private var googleClusterStrategy: MarkerClusterStrategy<GMSMarker>
    @State private var mapLibreClusterStrategy: MarkerClusterStrategy<MLNPointFeature>

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        markers: [MarkerState],
        selectedMarker: MarkerState?,
        onMapClick: @escaping (GeoPoint) -> Void,
        onInfoClick: ((PostOffice) -> Void)? = nil
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.onMapClick = onMapClick
        self.onInfoClick = onInfoClick
        self._googleClusterStrategy = State(
            initialValue: MarkerClusterStrategy<GMSMarker>(
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapLibreClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MLNPointFeature>(
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
    }

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
            if provider == .googleMaps {
                MarkerClusterGroup(strategy: googleClusterStrategy) {
                    for markerState in markers {
                        Marker(state: markerState)
                    }
                }
            } else {
                MarkerClusterGroup(strategy: mapLibreClusterStrategy) {
                    for markerState in markers {
                        Marker(state: markerState)
                    }
                }
            }

            if let marker = selectedMarker, let postOffice = marker.extra as? PostOffice {
                InfoBubble(marker: marker) {
                    PostOfficeInfoView(info: postOffice, onClick: onInfoClick)
                }
            }
        }
    }
}
