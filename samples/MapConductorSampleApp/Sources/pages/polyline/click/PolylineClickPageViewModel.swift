import Foundation
import MapConductorCore
import UIKit

@MainActor
final class PolylineClickPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let polylineState: PolylineState

    @Published private(set) var markers: [MarkerState] = []

    private let polylinePoints: [GeoPoint]
    private var nextMarkerId: Int = 0

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(latitude: 35.548852, longitude: 139.784086),
            zoom: 4.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.polylinePoints = [
            GeoPoint.fromLatLong(latitude: 35.548852, longitude: 139.784086),
            GeoPoint.fromLatLong(latitude: 37.615223, longitude: -122.389979),
            GeoPoint.fromLatLong(latitude: 21.324513, longitude: -157.925074)
        ]

        let polylineState = PolylineState(
            points: polylinePoints,
            id: "example_polyline",
            strokeColor: UIColor.red,
            strokeWidth: 4.0,
            geodesic: true
        )
        self.polylineState = polylineState
        polylineState.onClick = { [self] event in
            MCLog.map("PolylineClickPageViewModel.onClick id=\(event.state.id) lat=\(event.clicked.latitude) lng=\(event.clicked.longitude)")
            onPolylineClicked(event)
        }
    }

    func onPolylineClicked(_ clicked: PolylineEvent) {
        let markerId = "polyline-click-marker-\(nextMarkerId)"
        nextMarkerId += 1
        markers = markers + [
            MarkerState(
                position: GeoPoint.from(position: clicked.clicked),
                id: markerId,
                icon: DefaultMarkerIcon(fillColor: clicked.state.strokeColor),
                animation: .Drop
            )
        ]
        MCLog.map("PolylineClickPageViewModel.markers count=\(markers.count) appendedId=\(markerId)")
    }
}
