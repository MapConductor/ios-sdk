import MapKit
import MapConductorCore
import UIKit

@MainActor
final class MapKitPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<MKPolyline> {
    private weak var mapView: MKMapView?
    private var renderersByPolylineId: [String: MKPolylineRenderer] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> MKPolyline? {
        guard let mapView else { return nil }
        let geoPoints: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points, maxSegmentLength: 1000.0)
            : createLinearInterpolatePoints(state.points)

        var coordinates = geoPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        polyline.title = state.id

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = state.strokeColor
        renderer.lineWidth = CGFloat(state.strokeWidth)

        renderersByPolylineId[state.id] = renderer
        mapView.addOverlay(polyline)

        return polyline
    }

    override func updatePolylineProperties(
        polyline: MKPolyline,
        current: PolylineEntity<MKPolyline>,
        prev: PolylineEntity<MKPolyline>
    ) async -> MKPolyline? {
        guard let mapView else { return polyline }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // If points or geodesic changed, we need to recreate the polyline
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            mapView.removeOverlay(polyline)
            renderersByPolylineId.removeValue(forKey: current.state.id)
            return await createPolyline(state: current.state)
        }

        // Update renderer properties
        if let renderer = renderersByPolylineId[current.state.id] {
            if finger.strokeWidth != prevFinger.strokeWidth {
                renderer.lineWidth = CGFloat(current.state.strokeWidth)
            }
            if finger.strokeColor != prevFinger.strokeColor {
                renderer.strokeColor = current.state.strokeColor
            }
            // Request redraw
            renderer.setNeedsDisplay()
        }

        return polyline
    }

    override func removePolyline(entity: PolylineEntity<MKPolyline>) async {
        guard let mapView, let polyline = entity.polyline else { return }
        mapView.removeOverlay(polyline)
        renderersByPolylineId.removeValue(forKey: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let polyline = overlay as? MKPolyline,
              let id = polyline.title,
              let renderer = renderersByPolylineId[id] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByPolylineId.removeAll()
        mapView = nil
    }
}
