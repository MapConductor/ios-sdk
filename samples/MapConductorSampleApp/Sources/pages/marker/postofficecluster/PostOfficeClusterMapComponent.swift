import GoogleMaps
import MapConductorCore
import MapConductorForGoogleMaps
import MapConductorForMapLibre
import MapConductorForMapKit
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
        onInfoClick: ((PostOffice) -> Void)? = nil
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
