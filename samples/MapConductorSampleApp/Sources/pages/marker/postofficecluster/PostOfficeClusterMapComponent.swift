import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorMarkerClustering
import MapKit
import MapLibre
import SwiftUI
import UIKit

struct PostOfficeClusterMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onMapClick: (GeoPoint) -> Void
    let onInfoClick: ((PostOffice) -> Void)?
    @State private var googleClusterStrategy: MarkerClusterStrategy<GoogleMapActualMarker>
    @State private var mapLibreClusterStrategy: MarkerClusterStrategy<MapLibreActualMarker>
    @State private var mapKitClusterStrategy: MarkerClusterStrategy<MapKitActualMarker>

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        markers: [MarkerState],
        selectedMarker: MarkerState?,
        onMapClick: @escaping (GeoPoint) -> Void,
        onInfoClick: ((PostOffice) -> Void)? = nil,
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.onMapClick = onMapClick
        self.onInfoClick = onInfoClick
        self._googleClusterStrategy = State(
            initialValue: MarkerClusterStrategy<GoogleMapActualMarker>(
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapLibreClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MapLibreActualMarker>(
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapKitClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MapKitActualMarker>(
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
            mapKitState: mapKitState,
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
            } else if provider == .mapKit {
                MarkerClusterGroup(strategy: mapKitClusterStrategy) {
                    for markerState in markers {
                        Marker(state: markerState)
                    }
                }
            } else if provider == .mapLibre {
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
