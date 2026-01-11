import CoreLocation
import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<GMSGroundOverlay> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> GMSGroundOverlay? {
        guard let mapView else { return nil }
        guard let bounds = toCoordinateBounds(state.bounds) else { return nil }

        let overlay = GMSGroundOverlay(bounds: bounds, icon: state.image)
        overlay.opacity = Float(state.opacity)
        overlay.isTappable = false
        overlay.userData = state.id
        overlay.map = mapView
        return overlay
    }

    override func updateGroundImageProperties(
        groundImage: GMSGroundOverlay,
        current: GroundImageEntity<GMSGroundOverlay>,
        prev: GroundImageEntity<GMSGroundOverlay>
    ) async -> GMSGroundOverlay? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.bounds != prevFinger.bounds, let bounds = toCoordinateBounds(current.state.bounds) {
            groundImage.bounds = bounds
        }

        groundImage.opacity = Float(current.state.opacity)

        if finger.image != prevFinger.image {
            groundImage.icon = current.state.image
        }

        return groundImage
    }

    override func removeGroundImage(entity: GroundImageEntity<GMSGroundOverlay>) async {
        entity.groundImage?.map = nil
    }

    func unbind() {
        mapView = nil
    }

    private func toCoordinateBounds(_ bounds: GeoRectBounds) -> GMSCoordinateBounds? {
        guard let sw = bounds.southWest, let ne = bounds.northEast else { return nil }
        let swWrapped = GeoPoint.from(position: sw.wrap())
        let neWrapped = GeoPoint.from(position: ne.wrap())
        return GMSCoordinateBounds(
            coordinate: CLLocationCoordinate2D(latitude: swWrapped.latitude, longitude: swWrapped.longitude),
            coordinate: CLLocationCoordinate2D(latitude: neWrapped.latitude, longitude: neWrapped.longitude)
        )
    }
}
