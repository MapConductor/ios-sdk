import Foundation
import MapConductorCore
import UIKit

final class PolylinePageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let polylineState: PolylineState
    let wayPointMarkers: [MarkerState]

    private var polylinePoints: [GeoPoint]

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(latitude: 21.382314, longitude: -157.933097),
            zoom: 15.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.polylinePoints = [
            GeoPoint.fromLatLong(latitude: 21.382314, longitude: -157.933097),
            GeoPoint.fromLatLong(latitude: 21.385314, longitude: -157.930097),
            GeoPoint.fromLatLong(latitude: 21.387314, longitude: -157.935097),
            GeoPoint.fromLatLong(latitude: 21.380314, longitude: -157.937097),
            GeoPoint.fromLatLong(latitude: 21.378314, longitude: -157.930097),
            GeoPoint.fromLatLong(latitude: 21.382314, longitude: -157.933097)
        ]
        let initialPoints = polylinePoints

        self.polylineState = PolylineState(
            points: initialPoints,
            id: "example_polyline",
            strokeColor: UIColor.red,
            strokeWidth: 4.0,
            geodesic: true
        )

        let markers = initialPoints.enumerated().map { index, point in
            let markerColor: UIColor = (index == 0 || index == initialPoints.count - 1) ? .green : .yellow
            let label: String = (index == 0) ? "S" : (index == initialPoints.count - 1) ? "E" : "\(index)"

            let state = MarkerState(
                position: point,
                id: "waypoint_\(index)",
                extra: index,
                icon: DefaultMarkerIcon(
                    fillColor: markerColor,
                    strokeColor: UIColor.black,
                    label: label
                ),
                animation: nil,
                clickable: true,
                draggable: true,
                onClick: nil,
                onDragStart: nil,
                onDrag: nil,
                onDragEnd: nil,
                onAnimateStart: nil,
                onAnimateEnd: nil
            )
            return state
        }

        self.wayPointMarkers = markers
        self.wayPointMarkers.forEach { marker in
            marker.onDragStart = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
            marker.onDrag = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
            marker.onDragEnd = { [weak self] dragged in
                self?.onMarkerDrag(dragged)
            }
        }
    }

    func onMarkerDrag(_ dragged: MarkerState) {
        guard let index = dragged.extra as? Int else { return }
        guard index >= 0 && index < polylinePoints.count else { return }
        polylinePoints[index] = GeoPoint.from(position: dragged.position)
        polylineState.points = polylinePoints
    }
}
