import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<GMSPolyline> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> GMSPolyline? {
        guard let mapView else { return nil }
        let geoPoints: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points, maxSegmentLength: 1000.0)
            : createLinearInterpolatePoints(state.points)

        let path = GMSMutablePath()
        for point in geoPoints {
            path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }

        let polyline = GMSPolyline(path: path)
        polyline.strokeColor = state.strokeColor
        polyline.strokeWidth = CGFloat(state.strokeWidth)
        polyline.geodesic = state.geodesic
        polyline.isTappable = false
        polyline.map = mapView
        polyline.userData = state.id
        return polyline
    }

    override func updatePolylineProperties(
        polyline: GMSPolyline,
        current: PolylineEntity<GMSPolyline>,
        prev: PolylineEntity<GMSPolyline>
    ) async -> GMSPolyline? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            let geoPoints: [GeoPointProtocol] = current.state.geodesic
                ? createInterpolatePoints(current.state.points, maxSegmentLength: 1000.0)
                : createLinearInterpolatePoints(current.state.points)

            let path = GMSMutablePath()
            for point in geoPoints {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            polyline.path = path
            polyline.geodesic = current.state.geodesic
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            polyline.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            polyline.strokeColor = current.state.strokeColor
        }

        return polyline
    }

    override func removePolyline(entity: PolylineEntity<GMSPolyline>) async {
        entity.polyline?.map = nil
    }
}
