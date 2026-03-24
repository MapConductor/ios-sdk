import Foundation
import MapConductorCore
import UIKit

@MainActor
final class PostOfficeViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let postOfficeIcon: ImageIcon

    @Published var markers: [MarkerState] = []
    @Published var selectedMarker: MarkerState?
    @Published var isDataLoading = false

    // Scale icon based on zoom level, mirroring Android's MarkerTilingOptions.iconScaleCallback
    static func iconScale(zoom: Int) -> Double {
        if zoom > 12 { return 1.3 }
        if zoom > 10 { return 1.0 }
        if zoom > 8  { return 0.8 }
        if zoom > 5  { return 0.5 }
        return 0.2
    }

    init(postOfficeIcon: ImageIcon) {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(latitude: 35.68049, longitude: 139.76669),
            zoom: 10.0,
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
            let offices = await PostOfficeDataLoader().loadAllPostOffices()
            let nextMarkers = offices.enumerated().map { index, office in
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
            self.isDataLoading = false
        }
    }

    func clearSelection() {
        selectedMarker = nil
    }

    func onInfoClick(_ office: PostOffice, moveCameraTo: @escaping (MapCameraPosition) -> Void) {
        let camera = MapCameraPosition(
            position: office.position,
            zoom: 18.0,
            bearing: 0.0,
            tilt: 30.0,
            paddings: nil
        )
        moveCameraTo(camera)
    }
}
