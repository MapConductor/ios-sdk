import CoreLocation
import GoogleMaps
import MapConductorCore
import QuartzCore

final class GoogleMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: GMSMapView?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?

    init(mapView: GMSMapView) {
        self.mapView = mapView
        self.holder = AnyMapViewHolder(GoogleMapViewHolder(mapView: mapView))
    }

    func clearOverlays() async {
        mapView?.clear()
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
        let camera = position.toCameraPosition()
        mapView.moveCamera(GMSCameraUpdate.setCamera(camera))
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        let camera = position.toCameraPosition()
        let update = GMSCameraUpdate.setCamera(camera)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Double(duration) / 1000.0)
        mapView.animate(with: update)
        CATransaction.commit()
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
}
