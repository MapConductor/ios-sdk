import MapKit
import MapConductorCore
import UIKit

@MainActor
final class MapKitPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<MKPolygon> {
    private weak var mapView: MKMapView?
    private var renderersByPolygonId: [String: MKPolygonRenderer] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> MKPolygon? {
        guard let mapView else { return nil }
        let geoPoints: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points)
            : createLinearInterpolatePoints(state.points)

        var coordinates = geoPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
        polygon.title = state.id

        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.strokeColor = state.strokeColor
        renderer.lineWidth = CGFloat(state.strokeWidth)
        renderer.fillColor = state.fillColor

        renderersByPolygonId[state.id] = renderer
        mapView.addOverlay(polygon)

        return polygon
    }

    override func updatePolygonProperties(
        polygon: MKPolygon,
        current: PolygonEntity<MKPolygon>,
        prev: PolygonEntity<MKPolygon>
    ) async -> MKPolygon? {
        guard let mapView else { return polygon }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // If points or geodesic changed, we need to recreate the polygon
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            mapView.removeOverlay(polygon)
            renderersByPolygonId.removeValue(forKey: current.state.id)
            return await createPolygon(state: current.state)
        }

        // Update renderer properties
        if let renderer = renderersByPolygonId[current.state.id] {
            if finger.strokeWidth != prevFinger.strokeWidth {
                renderer.lineWidth = CGFloat(current.state.strokeWidth)
            }
            if finger.strokeColor != prevFinger.strokeColor {
                renderer.strokeColor = current.state.strokeColor
            }
            if finger.fillColor != prevFinger.fillColor {
                renderer.fillColor = current.state.fillColor
            }
            // Request redraw
            renderer.setNeedsDisplay()
        }

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<MKPolygon>) async {
        guard let mapView, let polygon = entity.polygon else { return }
        mapView.removeOverlay(polygon)
        renderersByPolygonId.removeValue(forKey: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let id = polygon.title,
              let renderer = renderersByPolygonId[id] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByPolygonId.removeAll()
        mapView = nil
    }
}
