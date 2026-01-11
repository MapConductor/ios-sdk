import CoreLocation
import MapKit
import MapConductorCore
import QuartzCore

final class MapKitViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: MKMapView?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?

    init(mapView: MKMapView) {
        self.mapView = mapView
        self.holder = AnyMapViewHolder(MapKitViewHolder(mapView: mapView))
    }

    func clearOverlays() async {
        guard let mapView = mapView else { return }
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) {
        cameraMoveStartListener = listener
    }

    func setCameraMoveListener(listener: OnCameraMoveHandler?) {
        cameraMoveListener = listener
    }

    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) {
        cameraMoveEndListener = listener
    }

    func setMapClickListener(listener: OnMapEventHandler?) {
        mapClickListener = listener
    }

    func setMapLongClickListener(listener: OnMapEventHandler?) {
        mapLongClickListener = listener
    }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView = mapView else { return }
        let camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: position.position.latitude,
                longitude: position.position.longitude
            ),
            fromDistance: altitudeFromZoom(position.zoom, latitude: position.position.latitude),
            pitch: position.tilt,
            heading: position.bearing
        )
        mapView.setCamera(camera, animated: false)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        let camera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: position.position.latitude,
                longitude: position.position.longitude
            ),
            fromDistance: altitudeFromZoom(position.zoom, latitude: position.position.latitude),
            pitch: position.tilt,
            heading: position.bearing
        )
        UIView.animate(withDuration: Double(duration) / 1000.0) {
            mapView.setCamera(camera, animated: false)
        }
    }

    func registerOverlayController(controller: any OverlayControllerProtocol) {}

    func notifyCameraMoveStart(_ cameraPosition: MapCameraPosition) {
        cameraMoveStartListener?(cameraPosition)
    }

    func notifyCameraMove(_ cameraPosition: MapCameraPosition) {
        cameraMoveListener?(cameraPosition)
    }

    func notifyCameraMoveEnd(_ cameraPosition: MapCameraPosition) {
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) {
        mapClickListener?(point)
    }

    // Convert zoom level to altitude (meters)
    // Formula: altitude = earthCircumference * cos(latitude) / (2^(zoom + 1) * π)
    // Simplified: altitude ≈ 40075017 * cos(latitude) / (2^zoom)
    private func altitudeFromZoom(_ zoom: Double, latitude: Double) -> CLLocationDistance {
        let earthCircumference: Double = 40075017.0
        let latitudeRadians = latitude * .pi / 180.0
        return earthCircumference * cos(latitudeRadians) / pow(2.0, zoom)
    }

    // Convert altitude (meters) to zoom level
    private func zoomFromAltitude(_ altitude: CLLocationDistance, latitude: Double) -> Double {
        let earthCircumference: Double = 40075017.0
        let latitudeRadians = latitude * .pi / 180.0
        return log2(earthCircumference * cos(latitudeRadians) / altitude)
    }
}
