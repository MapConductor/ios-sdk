import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
import MapConductorForMapbox
import MapConductorMarkerCluster
import MapKit
import MapLibre
import SwiftUI
import UIKit

struct PostOfficeClusterMapComponent: View {
    @Binding var provider: MapProvider
    @ObservedObject var googleState: GoogleMapViewState
    @ObservedObject var mapLibreState: MapLibreViewState
    @ObservedObject var mapKitState: MapKitViewState
    @ObservedObject var mapboxState: MapboxViewState

    let markers: [MarkerState]
    let selectedMarker: MarkerState?
    let onMapClick: (GeoPoint) -> Void
    let onInfoClick: ((PostOffice) -> Void)?

    @State private var googleClusterStrategy: MarkerClusterStrategy<GoogleMapActualMarker>
    @State private var mapLibreClusterStrategy: MarkerClusterStrategy<MapLibreActualMarker>
    @State private var mapKitClusterStrategy: MarkerClusterStrategy<MapKitActualMarker>
    @State private var mapboxClusterStrategy: MarkerClusterStrategy<MapboxActualMarker>

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        mapKitState: MapKitViewState,
        mapboxState: MapboxViewState,
        markers: [MarkerState],
        selectedMarker: MarkerState?,
        onMapClick: @escaping (GeoPoint) -> Void,
        onInfoClick: ((PostOffice) -> Void)? = nil
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.mapKitState = mapKitState
        self.mapboxState = mapboxState
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.onMapClick = onMapClick
        self.onInfoClick = onInfoClick

        // Android default is 90 physical pixels. iOS projection uses UIKit points,
        // so divide by screen scale to get the equivalent physical pixel coverage.
        let radiusPt = 90.0 / UIScreen.main.scale

        self._googleClusterStrategy = State(
            initialValue: MarkerClusterStrategy<GoogleMapActualMarker>(
                clusterRadiusPx: radiusPt,
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapLibreClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MapLibreActualMarker>(
                clusterRadiusPx: radiusPt,
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapKitClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MapKitActualMarker>(
                clusterRadiusPx: radiusPt,
                enableZoomAnimation: true,
                enablePanAnimation: true
            )
        )
        self._mapboxClusterStrategy = State(
            initialValue: MarkerClusterStrategy<MapboxActualMarker>(
                clusterRadiusPx: radiusPt,
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
            mapboxState: mapboxState,
            onMapClick: onMapClick,
            sdkInitialize: {
                GMSServices.provideAPIKey(SampleConfig.googleMapsApiKey)
                initializeMapbox(accessToken: SampleConfig.mapboxAccessToken)
            }
        ) {
            clusterLayer()

            if let marker = selectedMarker, let postOffice = marker.extra as? PostOffice {
                InfoBubble(marker: marker) {
                    PostOfficeInfoView(info: postOffice, onClick: onInfoClick)
                }
            }
        }
    }

    // ここが「クロージャで分岐」(ただし AnyView ではなく MapViewContentBuilder の世界)
    @MapViewContentBuilder
    private func clusterLayer() -> MapViewContent {
        if provider == .googleMaps {
            MarkerClusterGroup(strategy: googleClusterStrategy) {
                markerItems()
            }
        } else if provider == .mapKit {
            MarkerClusterGroup(strategy: mapKitClusterStrategy) {
                markerItems()
            }
        } else if provider == .mapLibre {
            MarkerClusterGroup(strategy: mapLibreClusterStrategy) {
                markerItems()
            }
        } else if provider == .mapbox {
            MarkerClusterGroup(strategy: mapboxClusterStrategy) {
                markerItems()
            }
        }
    }

    // Marker の for ループを 1 箇所に集約
    @MapViewContentBuilder
    private func markerItems() -> MapViewContent {
        for markerState in markers {
            Marker(state: markerState)
        }
    }
}
