import Foundation
import MapConductorCore
import MapKit
import UIKit

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

    func openDirectionsInAppleMaps(for marker: MarkerState) {

        let latitude = marker.position.latitude
        let longitude = marker.position.longitude

        // Get store name if available
        let storeName = (marker.extra as? StoreInfo)?.name ?? "Destination"

        // Build Apple Maps URL with directions - simpler approach
        // Format: http://maps.apple.com/?daddr=latitude,longitude&dirflg=d
        let urlString = "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d"

        guard let url = URL(string: urlString) else {
            return
        }


        UIApplication.shared.open(url, options: [:]) { success in
            print("DEBUG: Apple Maps open result: \(success)")
        }
    }
}
