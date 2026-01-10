import Foundation
import MapConductorCore
import UIKit

@MainActor
final class PostOfficeClusterPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let postOfficeIcon: ImageIcon

    @Published var markers: [MarkerState] = []
    @Published var selectedMarker: MarkerState?
    @Published var isDataLoading: Bool = false

    init(postOfficeIcon: ImageIcon) {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(
                latitude: 35.68049,
                longitude: 139.76669
            ),
            zoom: 13.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
        self.postOfficeIcon = postOfficeIcon
    }
    
    
    func loadPostOffices() {
        if !markers.isEmpty { return }
        isDataLoading = true
        
        Task { [weak self] in
            guard let self else { return }
            let nextMarkers = tokyoPostOffices.enumerated().map { index, office in
                MarkerState(
                    position: office.position,
                    id: "postoffice-\(index)",
                    extra: office,
                    icon: postOfficeIcon,
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
