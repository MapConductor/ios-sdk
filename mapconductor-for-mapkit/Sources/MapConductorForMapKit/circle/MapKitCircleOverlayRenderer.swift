import CoreLocation
import MapKit
import MapConductorCore
import UIKit

@MainActor
final class MapKitCircleOverlayRenderer: AbstractCircleOverlayRenderer<MKPolygon> {
    private weak var mapView: MKMapView?
    private var renderersByCircleId: [String: MKPolygonRenderer] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createCircle(state: CircleState) async -> MKPolygon? {
        guard let mapView else { return nil }
        let center = CLLocationCoordinate2D(latitude: state.center.latitude, longitude: state.center.longitude)
        let points = makeCirclePoints(center: center, radiusMeters: state.radiusMeters, geodesic: state.geodesic)

        let polygon = MKPolygon(coordinates: points, count: points.count)
        polygon.title = state.id

        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.strokeColor = state.strokeColor
        renderer.lineWidth = CGFloat(state.strokeWidth)
        renderer.fillColor = state.fillColor

        renderersByCircleId[state.id] = renderer
        mapView.addOverlay(polygon)

        return polygon
    }

    override func updateCircleProperties(
        circle: MKPolygon,
        current: CircleEntity<MKPolygon>,
        prev: CircleEntity<MKPolygon>
    ) async -> MKPolygon? {
        guard let mapView else { return circle }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // If center, radius, or geodesic changed, we need to recreate the polygon
        let needsRecreation =
            finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic

        if needsRecreation {
            // Remove old overlay and create new one
            mapView.removeOverlay(circle)
            renderersByCircleId.removeValue(forKey: current.state.id)
            return await createCircle(state: current.state)
        }

        // Update renderer properties
        if let renderer = renderersByCircleId[current.state.id] {
            if finger.strokeColor != prevFinger.strokeColor {
                renderer.strokeColor = current.state.strokeColor
            }
            if finger.strokeWidth != prevFinger.strokeWidth {
                renderer.lineWidth = CGFloat(current.state.strokeWidth)
            }
            if finger.fillColor != prevFinger.fillColor {
                renderer.fillColor = current.state.fillColor
            }
            // Request redraw
            renderer.setNeedsDisplay()
        }

        return circle
    }

    override func removeCircle(entity: CircleEntity<MKPolygon>) async {
        guard let mapView, let circle = entity.circle else { return }
        mapView.removeOverlay(circle)
        renderersByCircleId.removeValue(forKey: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let id = polygon.title,
              let renderer = renderersByCircleId[id] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByCircleId.removeAll()
        mapView = nil
    }
}

private let circleSegments = 64
private let earthRadiusMeters = 6_371_000.0

private func makeCirclePoints(
    center: CLLocationCoordinate2D,
    radiusMeters: Double,
    geodesic: Bool
) -> [CLLocationCoordinate2D] {
    return geodesic
        ? generateGeodesicCirclePoints(center: center, radiusMeters: radiusMeters)
        : generateNonGeodesicCirclePoints(center: center, radiusMeters: radiusMeters)
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
