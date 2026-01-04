import Foundation
import MapConductorCore
import UIKit

final class CirclePageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let circleCenter: GeoPoint
    let centerMarker: MarkerState
    let edgeMarker: MarkerState
    let circleState: CircleState

    @Published var fillOpacity: Double
    @Published var strokeWidth: Double
    @Published var message: String

    private let colors: [UIColor]
    private var fillColorIndex = 0

    init() {
        let initialFillOpacity = 0.3
        let initialStrokeWidth = 3.0
        let center = GeoPoint(latitude: 21.382314, longitude: -157.933097)
        let edge = CirclePageViewModel.calculatePositionAtDistance(
            center: center,
            distanceMeters: 1000.0,
            bearingDegrees: 90.0
        )

        self.circleCenter = center
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 12.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.colors = [
            UIColor.blue,
            UIColor.red,
            UIColor.green,
            UIColor.cyan,
            UIColor.lightGray,
            UIColor.magenta
        ]

        self.centerMarker = MarkerState(
            position: center,
            id: "center_marker",
            icon: DefaultMarkerIcon(
                fillColor: UIColor.red,
                strokeColor: UIColor.white,
                label: "C"
            ),
            draggable: false
        )

        self.edgeMarker = MarkerState(
            position: edge,
            id: "edge_marker",
            icon: DefaultMarkerIcon(
                fillColor: UIColor.green,
                strokeColor: UIColor.white,
                label: "E"
            ),
            draggable: true
        )

        self.circleState = CircleState(
            center: center,
            radiusMeters: CirclePageViewModel.computeDistanceBetween(center, edge),
            strokeColor: UIColor.blue.withAlphaComponent(0.5),
            strokeWidth: initialStrokeWidth,
            fillColor: UIColor.blue.withAlphaComponent(initialFillOpacity),
            id: "circle",
            onClick: nil
        )

        self.fillOpacity = initialFillOpacity
        self.strokeWidth = initialStrokeWidth
        self.message = "Tap the circle or drag the edge marker."

        self.edgeMarker.onDragStart = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.edgeMarker.onDrag = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.edgeMarker.onDragEnd = { [weak self] dragged in
            self?.onMarkerMove(dragged)
        }
        self.circleState.onClick = { [weak self] event in
            self?.onCircleClick(event)
        }
    }

    func onCircleClick(_ event: CircleEvent) {
        fillColorIndex = (fillColorIndex + 1) % colors.count
        updateCircleFillColor()
        message = "Circle clicked - Radius: \(Int(radiusMeters))m"
    }

    func onMarkerMove(_ dragged: MarkerState) {
        edgeMarker.position = dragged.position
        circleState.radiusMeters = radiusMeters
    }

    func updateCircleFillColor() {
        circleState.fillColor = colors[fillColorIndex].withAlphaComponent(fillOpacity)
    }

    func updateCircleStrokeWidth() {
        circleState.strokeWidth = strokeWidth
    }

    private var radiusMeters: Double {
        CirclePageViewModel.computeDistanceBetween(circleCenter, edgeMarker.position)
    }

    private static func computeDistanceBetween(_ from: GeoPointProtocol, _ to: GeoPointProtocol) -> Double {
        let radius = 6_371_009.0
        let lat1 = degreesToRadians(from.latitude)
        let lat2 = degreesToRadians(to.latitude)
        let deltaLat = lat2 - lat1
        let deltaLng = degreesToRadians(to.longitude - from.longitude)

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return radius * c
    }

    private static func calculatePositionAtDistance(
        center: GeoPointProtocol,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> GeoPoint {
        let radius = 6_371_009.0
        let bearing = degreesToRadians(bearingDegrees)
        let angularDistance = distanceMeters / radius
        let lat1 = degreesToRadians(center.latitude)
        let lon1 = degreesToRadians(center.longitude)

        let sinLat1 = sin(lat1)
        let cosLat1 = cos(lat1)
        let sinAngular = sin(angularDistance)
        let cosAngular = cos(angularDistance)

        let lat2 = asin(sinLat1 * cosAngular + cosLat1 * sinAngular * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sinAngular * cosLat1,
            cosAngular - sinLat1 * sin(lat2)
        )

        let latitude = radiansToDegrees(lat2)
        let longitude = radiansToDegrees(lon2)
        let wrapped = GeoPoint(latitude: latitude, longitude: longitude).wrap()
        return GeoPoint.from(position: wrapped)
    }
}

private func degreesToRadians(_ degrees: Double) -> Double {
    degrees * .pi / 180.0
}

private func radiansToDegrees(_ radians: Double) -> Double {
    radians * 180.0 / .pi
}
