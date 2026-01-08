import Foundation
import MapConductorCore
import UIKit

@MainActor
final class PostOfficeClusterPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published var markers: [MarkerState] = []
    @Published var selectedMarker: MarkerState?
    @Published var isDataLoading: Bool = false

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(
                latitude: 35.68049,
                longitude: 139.76669
            ),
            zoom: 10.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func loadPostOffices() {
        if !markers.isEmpty { return }
        isDataLoading = true
        Task { [weak self] in
            guard let self else { return }
            let icon = DefaultMarkerIcon(fillColor: UIColor.systemOrange, label: "P")
            let nextMarkers = tokyoPostOffices.enumerated().map { index, office in
                MarkerState(
                    position: office.position,
                    id: "postoffice-\(index)",
                    extra: office,
                    icon: icon,
                    animation: nil,
                    clickable: true,
                    draggable: false,
                    onClick: { [weak self] marker in
                        self?.selectedMarker = marker
                    }
                )
            }
            self.markers = nextMarkers
            MCLog.marker("PostOfficeClusterPageViewModel.loaded markers=\(nextMarkers.count)")
            self.isDataLoading = false
        }
    }

    func clearSelection() {
        selectedMarker = nil
    }
}
