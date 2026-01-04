import CoreLocation
import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapCircleOverlayRenderer: AbstractCircleOverlayRenderer<GMSPolygon> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createCircle(state: CircleState) async -> GMSPolygon? {
        guard let mapView else { return nil }
        let center = CLLocationCoordinate2D(latitude: state.center.latitude, longitude: state.center.longitude)
        let adjustedRadius = adjustedRadiusMeters(for: state, center: center)
        let path = makeCirclePath(center: center, radiusMeters: adjustedRadius, geodesic: state.geodesic)

        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = state.strokeColor
        polygon.strokeWidth = CGFloat(state.strokeWidth)
        polygon.fillColor = state.fillColor
        polygon.isTappable = state.clickable
        polygon.zIndex = Int32(state.zIndex ?? 0)
        polygon.geodesic = state.geodesic
        polygon.map = mapView
        polygon.userData = state.id
        return polygon
    }

    override func updateCircleProperties(
        circle: GMSPolygon,
        current: CircleEntity<GMSPolygon>,
        prev: CircleEntity<GMSPolygon>
    ) async -> GMSPolygon? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic ||
            finger.strokeWidth != prevFinger.strokeWidth {
            let center = CLLocationCoordinate2D(latitude: current.state.center.latitude, longitude: current.state.center.longitude)
            let adjustedRadius = adjustedRadiusMeters(for: current.state, center: center)
            circle.path = makeCirclePath(
                center: center,
                radiusMeters: adjustedRadius,
                geodesic: current.state.geodesic
            )
            circle.geodesic = current.state.geodesic
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            circle.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            circle.strokeColor = current.state.strokeColor
        }

        if finger.fillColor != prevFinger.fillColor {
            circle.fillColor = current.state.fillColor
        }

        if finger.clickable != prevFinger.clickable {
            circle.isTappable = current.state.clickable
        }

        if finger.zIndex != prevFinger.zIndex {
            circle.zIndex = Int32(current.state.zIndex ?? 0)
        }

        return circle
    }

    override func removeCircle(entity: CircleEntity<GMSPolygon>) async {
        entity.circle?.map = nil
    }

    private func adjustedRadiusMeters(for state: CircleState, center: CLLocationCoordinate2D) -> Double {
        let strokeWidth = max(0.0, state.strokeWidth)
        guard strokeWidth > 0.0 else { return state.radiusMeters }
        guard let mapView else { return state.radiusMeters }
        let projection = mapView.projection
        let centerPoint = projection.point(for: center)
        let offsetPoint = CGPoint(x: centerPoint.x, y: centerPoint.y - CGFloat(strokeWidth / 2.0))
        let offsetCoord = projection.coordinate(for: offsetPoint)
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let offsetLocation = CLLocation(latitude: offsetCoord.latitude, longitude: offsetCoord.longitude)
        let strokeMeters = centerLocation.distance(from: offsetLocation)
        return state.radiusMeters + strokeMeters
    }
}

private let circleSegments = 64
private let earthRadiusMeters = 6_371_000.0

private func makeCirclePath(
    center: CLLocationCoordinate2D,
    radiusMeters: Double,
    geodesic: Bool
) -> GMSPath {
    let points = geodesic
        ? generateGeodesicCirclePoints(center: center, radiusMeters: radiusMeters)
        : generateNonGeodesicCirclePoints(center: center, radiusMeters: radiusMeters)

    let path = GMSMutablePath()
    for point in points {
        path.add(point)
    }
    return path
}

private func generateGeodesicCirclePoints(
    center: CLLocationCoordinate2D,
    radiusMeters: Double
) -> [CLLocationCoordinate2D] {
    let centerLat = degreesToRadians(center.latitude)
    let centerLng = degreesToRadians(center.longitude)
    let angularDistance = radiusMeters / earthRadiusMeters

    var points: [CLLocationCoordinate2D] = []
    points.reserveCapacity(circleSegments + 1)

    for i in 0...circleSegments {
        let bearing = 2.0 * Double.pi * Double(i) / Double(circleSegments)
        let lat = asin(
            sin(centerLat) * cos(angularDistance) +
                cos(centerLat) * sin(angularDistance) * cos(bearing)
        )
        let lng = centerLng + atan2(
            sin(bearing) * sin(angularDistance) * cos(centerLat),
            cos(angularDistance) - sin(centerLat) * sin(lat)
        )
        points.append(
            CLLocationCoordinate2D(
                latitude: radiansToDegrees(lat),
                longitude: radiansToDegrees(lng)
            )
        )
    }

    return points
}

private func generateNonGeodesicCirclePoints(
    center: CLLocationCoordinate2D,
    radiusMeters: Double
) -> [CLLocationCoordinate2D] {
    let centerLatRad = degreesToRadians(center.latitude)
    let latDegreesPerMeter = 1.0 / (earthRadiusMeters * Double.pi / 180.0)
    let lngDegreesPerMeter = 1.0 / (earthRadiusMeters * Double.pi / 180.0 * cos(centerLatRad))

    var points: [CLLocationCoordinate2D] = []
    points.reserveCapacity(circleSegments + 1)

    for i in 0...circleSegments {
        let angle = 2.0 * Double.pi * Double(i) / Double(circleSegments)
        let dx = radiusMeters * cos(angle)
        let dy = radiusMeters * sin(angle)

        let latitude = center.latitude + dy * latDegreesPerMeter
        let longitude = center.longitude + dx * lngDegreesPerMeter
        points.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    return points
}

private func degreesToRadians(_ degrees: Double) -> Double {
    degrees * .pi / 180.0
}

private func radiansToDegrees(_ radians: Double) -> Double {
    radians * 180.0 / .pi
}
