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

    @State private var markerList: [MarkerState]

    init(
        provider: Binding<MapProvider>,
        googleState: GoogleMapViewState,
        mapLibreState: MapLibreViewState,
        markers: [MarkerState],
        selectedMarker: MarkerState?,
        onDirectionButtonClick: @escaping (MarkerState) -> Void,
        onMapClick: @escaping (GeoPoint) -> Void
    ) {
        self._provider = provider
        self.googleState = googleState
        self.mapLibreState = mapLibreState
        self.markers = markers
        self.selectedMarker = selectedMarker
        self.onDirectionButtonClick = onDirectionButtonClick
        self.onMapClick = onMapClick
        self._markerList = State(initialValue: StoreMapComponent.prepareMarkers(markers))
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
            var content = MapViewContent()
            content.markers = markerList.map { Marker(state: $0) }
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

    private static func prepareMarkers(_ markers: [MarkerState]) -> [MarkerState] {
        let icons: [String: ImageDefaultIcon] = [
            "coffee_bean": makeStoreIcon(named: "coffee_bean"),
            "honolulu_coffee": makeStoreIcon(named: "honolulu_coffee"),
            "coffee_extra": makeStoreIcon(named: "coffee_extra"),
            "starbucks": makeStoreIcon(named: "starbucks"),
        ].compactMapValues { $0 }

        return markers.map { state in
            guard let info = state.extra as? StoreInfo else { return state }
            if let icon = icons[info.store] {
                return state.copy(icon: icon)
            }
            return state
        }
    }

    private static func makeStoreIcon(named name: String) -> ImageDefaultIcon? {
        guard let image = loadPngImage(named: name) else { return nil }
        return ImageDefaultIcon(
            backgroundImage: image,
            strokeColor: .white,
            strokeWidth: DefaultMarkerIcon.defaultStrokeWidth,
            scale: 1.0,
            infoAnchor: DefaultMarkerIcon.defaultInfoAnchor,
            iconSize: DefaultMarkerIcon.defaultIconSize,
            debug: false
        )
    }

    private static func loadPngImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
}
