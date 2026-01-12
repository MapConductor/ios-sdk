import Foundation
import CoreLocation
import MapKit
import MapConductorCore
import QuartzCore

final class MapKitViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: MKMapView?
    private let tileSizePoints: Double = 256.0
    private let minCosLat: Double = 0.01

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
        if abs(position.tilt) < 0.01, mapView.bounds.isEmpty {
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                _ = self.applyTopDownZoom(position: position, mapView: mapView, animated: false)
            }
        }
        if applyTopDownZoom(position: position, mapView: mapView, animated: false) {
            return
        }
        let camera = position.toMKMapCamera()
        mapView.setCamera(camera, animated: false)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        let durationSeconds = Double(duration) / 1000.0

        if abs(position.tilt) < 0.01, mapView.bounds.isEmpty {
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                _ = self.applyTopDownZoom(position: position, mapView: mapView, animated: true, duration: durationSeconds)
            }
        }
        if applyTopDownZoom(position: position, mapView: mapView, animated: true, duration: durationSeconds) {
            return
        }
        let camera = position.toMKMapCamera()
        UIView.animate(withDuration: durationSeconds) {
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

    private func applyTopDownZoom(position: MapCameraPosition, mapView: MKMapView, animated: Bool, duration: Double = 0.0) -> Bool {
        // For top-down cameras, setVisibleMapRect can match Google/WebMercator zoom precisely (including latitude scaling)
        // based on the viewport size. This avoids relying on a single magic constant (zoom0Altitude) for MapKit.
        let isTopDown = abs(position.tilt) < 0.01
        guard isTopDown, !mapView.bounds.isEmpty else { return false }

        let widthPoints = Double(mapView.bounds.width)
        let heightPoints = Double(mapView.bounds.height)
        guard widthPoints > 0, heightPoints > 0 else { return false }

        let centerLat = max(-85.0, min(position.position.latitude, 85.0))
        let latitudeRadians = centerLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let metersPerPoint = (Earth.circumferenceMeters * cosLat) / (tileSizePoints * pow(2.0, position.zoom))
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return false }

        let widthMeters = metersPerPoint * widthPoints
        let heightMeters = metersPerPoint * heightPoints

        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(centerLat)
        guard pointsPerMeter > 0 else { return false }
        let mapRectWidth = widthMeters * pointsPerMeter
        let mapRectHeight = heightMeters * pointsPerMeter
        guard mapRectWidth.isFinite, mapRectHeight.isFinite, mapRectWidth > 0, mapRectHeight > 0 else { return false }

        let centerCoordinate = CLLocationCoordinate2D(latitude: position.position.latitude, longitude: position.position.longitude)
        let centerPoint = MKMapPoint(centerCoordinate)
        let rect = MKMapRect(
            x: centerPoint.x - mapRectWidth / 2.0,
            y: centerPoint.y - mapRectHeight / 2.0,
            width: mapRectWidth,
            height: mapRectHeight
        )

        // Apply heading explicitly (including 0) without changing scale.
        var camera = mapView.camera
        camera.centerCoordinate = centerCoordinate
        camera.heading = position.bearing
        camera.pitch = 0

        if animated && duration > 0 {
            // Use UIView.animate to respect the specified duration
            UIView.animate(withDuration: duration) {
                mapView.setVisibleMapRect(rect, edgePadding: .zero, animated: false)
                mapView.setCamera(camera, animated: false)
            }
        } else {
            // Use MapKit's default animation or no animation
            mapView.setVisibleMapRect(rect, edgePadding: .zero, animated: animated)
            mapView.setCamera(camera, animated: animated)
        }

        return true
    }
}
