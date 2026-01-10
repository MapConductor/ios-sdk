import Foundation
import MapConductorCore

final class StoreMapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let markerList: [MarkerState]
    @Published var mapViewState: Any? = nil

    @Published var selectedMarker: MarkerState? = nil

    init() {
        self.initCameraPosition = StoreDemoData.initCameraPosition
        self.markerList = StoreDemoData.markerStates()
        self.markerList.forEach { marker in
            marker.onClick = { [weak self] clicked in
                self?.onMarkerClick(clicked)
            }
        }
    }

    func onMapViewChanged(provider: MapProvider) {
        // Keep the behavior symmetric with Android: switching providers resets selection.
        selectedMarker = nil
        mapViewState = provider
    }

    func onMarkerClick(_ clicked: MarkerState) {
        selectedMarker = clicked
    }

    func onMapClick(_ clicked: GeoPoint) {
        selectedMarker = nil
    }

    func directionURL(for marker: MarkerState) -> URL? {
        let query = (marker.extra as? StoreInfo)?.address ?? "\(marker.position.latitude),\(marker.position.longitude)"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }
}
