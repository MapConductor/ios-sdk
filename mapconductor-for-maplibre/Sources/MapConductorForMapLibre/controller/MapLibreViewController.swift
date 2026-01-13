import CoreLocation
import MapLibre
import MapConductorCore
import QuartzCore

final class MapLibreViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: MLNMapView?
    private var cameraAnimator: CameraAnimator?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?

    init(mapView: MLNMapView) {
        self.mapView = mapView
        self.holder = AnyMapViewHolder(MapLibreViewHolder(mapView: mapView))
    }

    func clearOverlays() async {
        guard let mapView = mapView else { return }
        if let annotations = mapView.annotations {
            mapView.removeAnnotations(annotations)
        }
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

        // Set zoom/center/bearing first, then apply pitch via setCamera.
        // Note: MLNMapView.camera is a copy; mutating mapView.camera.pitch does not affect the map.
        mapView.setCenter(
            CLLocationCoordinate2D(
                latitude: position.position.latitude,
                longitude: position.position.longitude
            ),
            zoomLevel: position.adjustedZoomForMapLibre(),
            direction: position.bearing,
            animated: false
        )

        let camera = mapView.camera
        camera.pitch = position.tilt
        mapView.setCamera(camera, animated: false)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        let durationSeconds = max(0.0, Double(duration) / 1000.0)
        guard durationSeconds > 0 else {
            moveCamera(position: position)
            return
        }

        cameraAnimator?.stop()
        let from = mapView.toMapCameraPosition()
        cameraAnimator = CameraAnimator(
            mapView: mapView,
            from: from,
            to: position,
            duration: durationSeconds
        )
        cameraAnimator?.start()
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

private final class CameraAnimator {
    private weak var mapView: MLNMapView?
    private let from: MapCameraPosition
    private let to: MapCameraPosition
    private let duration: TimeInterval
    private let zoomArcAmplitude: Double
    private var displayLink: CADisplayLink?
    private let startTime: CFTimeInterval

    init(
        mapView: MLNMapView,
        from: MapCameraPosition,
        to: MapCameraPosition,
        duration: TimeInterval,
        zoomArcAmplitude: Double = 2.5
    ) {
        self.mapView = mapView
        self.from = from
        self.to = to
        self.duration = max(duration, 0.01)
        self.zoomArcAmplitude = zoomArcAmplitude
        self.startTime = CACurrentMediaTime()
    }

    func start() {
        let displayLink = CADisplayLink(target: self, selector: #selector(step(_:)))
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ displayLink: CADisplayLink) {
        guard let mapView = mapView else {
            stop()
            return
        }

        let elapsed = CACurrentMediaTime() - startTime
        let linear = min(1.0, elapsed / duration)
        let t = easeInOut(linear)

        let latitude = lerp(from.position.latitude, to.position.latitude, t)
        let longitude = lerp(from.position.longitude, to.position.longitude, t)
        let zoom = lerp(from.zoom, to.zoom, t) + zoomArc(t)
        let bearing = lerpAngle(from.bearing, to.bearing, t)
        let tilt = lerp(from.tilt, to.tilt, t)

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let currentPos = MapCameraPosition(
            position: GeoPoint(latitude: latitude, longitude: longitude, altitude: 0),
            zoom: zoom,
            bearing: bearing,
            tilt: tilt
        )
        mapView.setCenter(
            center,
            zoomLevel: currentPos.adjustedZoomForMapLibre(),
            animated: false
        )
        let camera = mapView.camera
        camera.heading = bearing
        camera.pitch = tilt
        mapView.setCamera(camera, animated: false)

        if t >= 1.0 {
            stop()
        }
    }

    private func lerp(_ from: Double, _ to: Double, _ t: Double) -> Double {
        from + (to - from) * t
    }

    private func lerpAngle(_ from: Double, _ to: Double, _ t: Double) -> Double {
        let delta = ((to - from + 540).truncatingRemainder(dividingBy: 360)) - 180
        return from + delta * t
    }

    private func zoomArc(_ t: Double) -> Double {
        guard zoomArcAmplitude > 0 else { return 0 }
        return -zoomArcAmplitude * sin(.pi * t)
    }

    private func easeInOut(_ t: Double) -> Double {
        guard t > 0 && t < 1 else { return t }
        return t * t * (3 - 2 * t)
    }
}
