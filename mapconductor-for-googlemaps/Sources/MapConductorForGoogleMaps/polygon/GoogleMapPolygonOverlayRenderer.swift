import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<GMSPolygon> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> GMSPolygon? {
        guard let mapView else { return nil }
        let geoPoints = resolvedPoints(for: state)

        let path = GMSMutablePath()
        for point in geoPoints {
            path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }

        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = state.strokeColor
        polygon.strokeWidth = CGFloat(state.strokeWidth)
        polygon.fillColor = state.fillColor
        polygon.geodesic = state.geodesic
        polygon.map = mapView
        polygon.userData = state.id
        return polygon
    }

    override func updatePolygonProperties(
        polygon: GMSPolygon,
        current: PolygonEntity<GMSPolygon>,
        prev: PolygonEntity<GMSPolygon>
    ) async -> GMSPolygon? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            let geoPoints = resolvedPoints(for: current.state)

            let path = GMSMutablePath()
            for point in geoPoints {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            polygon.path = path
            polygon.geodesic = current.state.geodesic
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            polygon.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            polygon.strokeColor = current.state.strokeColor
        }

        if finger.fillColor != prevFinger.fillColor {
            polygon.fillColor = current.state.fillColor
        }

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<GMSPolygon>) async {
        entity.polygon?.map = nil
    }

    private func resolvedPoints(for state: PolygonState) -> [GeoPointProtocol] {
        let interpolated: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points, maxSegmentLength: 1000.0)
            : createLinearInterpolatePoints(state.points)
        // Google Maps iOS has practical limits on polygon point counts; fallback to raw points if too large.
        if interpolated.count > 10_000 {
            return state.points
        }
        return interpolated
    }
}
