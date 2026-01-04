import CoreGraphics
import CoreLocation
import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapMarkerOverlayRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = GMSMarker

    weak var mapView: GMSMapView?
    private let markerManager: MarkerManager<GMSMarker>
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(mapView: GMSMapView?, markerManager: MarkerManager<GMSMarker>) {
        self.mapView = mapView
        self.markerManager = markerManager
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [GMSMarker?] {
        guard let mapView else { return [] }
        MCLog.marker("GoogleMapMarkerOverlayRenderer.onAdd count=\(data.count)")
        return data.map { params in
            let marker = GMSMarker()
            marker.map = mapView
            marker.userData = params.state.id
            apply(state: params.state, bitmapIcon: params.bitmapIcon, to: marker)
            return marker
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<GMSMarker>]) async -> [GMSMarker?] {
        if !data.isEmpty { MCLog.marker("GoogleMapMarkerOverlayRenderer.onChange count=\(data.count)") }
        return data.map { params in
            guard let marker = params.prev.marker else { return nil }
            apply(state: params.current.state, bitmapIcon: params.bitmapIcon, to: marker)
            return marker
        }
    }

    func onRemove(data: [MarkerEntity<GMSMarker>]) async {
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
            entity.marker?.map = nil
        }
    }

    func onAnimate(entity: MarkerEntity<GMSMarker>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let mapView, let marker = entity.marker else { return }
        guard let animation = entity.state.getAnimation() else { return }

        MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate start id=\(entity.state.id) anim=\(animation) bounds=\(String(describing: mapView.bounds))")
        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=windowOrBounds")
            await deferAnimate(entity: entity)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        let targetPoint = mapView.projection.point(for: target)
        let startPoint = CGPoint(x: targetPoint.x, y: 0)
        let startCoord = mapView.projection.coordinate(for: startPoint)
        let startBackPoint = mapView.projection.point(for: startCoord)

        MCLog.marker(
            "GoogleMapMarkerOverlayRenderer.onAnimate id=\(entity.state.id) targetPoint=\(String(describing: targetPoint)) startPoint=\(String(describing: startPoint)) startBackPoint=\(String(describing: startBackPoint))"
        )

        // Sanity check: converting (x,0) -> coord -> point should come back near y=0.
        // If projection isn't ready, it can collapse and return a point nowhere near the top.
        if !targetPoint.x.isFinite || !targetPoint.y.isFinite || !startBackPoint.x.isFinite || !startBackPoint.y.isFinite {
            MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=nonFiniteProjection")
            await deferAnimate(entity: entity)
            return
        }

        let deltaX = abs(startBackPoint.x - targetPoint.x)
        let deltaY = abs(startBackPoint.y - 0.0)
        if deltaX > 4.0 || deltaY > 4.0 {
            MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=projectionMismatch dx=\(deltaX) dy=\(deltaY)")
            await deferAnimate(entity: entity)
            return
        }

        // If projection isn't ready yet, `startCoord` can collapse to the target coordinate,
        // resulting in a "no-op" animation on the very first request. Retry a few frames.
        if targetPoint.y > 1,
           abs(startCoord.latitude - target.latitude) < 1e-10,
           abs(startCoord.longitude - target.longitude) < 1e-10 {
            MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=projectionNotReady")
            await deferAnimate(entity: entity)
            return
        }

        let duration: CFTimeInterval = animation == .Drop ? 0.3 : 2.0

        // Prevent implicit animations on map assignment / initial position.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        let oldMap = marker.map
        marker.map = nil
        marker.position = startCoord
        marker.map = oldMap
        CATransaction.commit()

        animateStartListener?(entity.state)

        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)
        let pathPoints = animation == .Bounce ? bouncePath(for: mapView, target: target) : nil

        let runner = MarkerAnimationRunner(
            animation: animation,
            duration: duration,
            startPoint: startGeoPoint,
            targetPoint: targetGeoPoint,
            pathPoints: pathPoints,
            onUpdate: { point in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                CATransaction.setAnimationDuration(0)
                marker.position = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                CATransaction.commit()
            },
            onCompletion: { [weak self] in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                CATransaction.setAnimationDuration(0)
                marker.position = target
                CATransaction.commit()

                entity.state.animate(nil)
                self?.markerAnimationRunners[entity.state.id] = nil
                MCLog.marker("GoogleMapMarkerOverlayRenderer.onAnimate end id=\(entity.state.id)")
                self?.animateEndListener?(entity.state)
            }
        )
        markerAnimationRunners[entity.state.id] = runner
        runner.start()
    }

    private func deferAnimate(entity: MarkerEntity<GMSMarker>) async {
        let id = entity.state.id
        let attempts = (deferredAnimateAttemptsById[id] ?? 0) + 1
        deferredAnimateAttemptsById[id] = attempts
        MCLog.marker("GoogleMapMarkerOverlayRenderer.deferAnimate id=\(id) attempt=\(attempts)")
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            MCLog.marker("GoogleMapMarkerOverlayRenderer.deferAnimate id=\(id) givingUp")
            return
        }
        try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame
        await onAnimate(entity: entity)
    }

    func onPostProcess() async {
        // No-op: Google Maps applies changes directly on each marker.
        _ = markerManager
    }

    func unbind() {
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        mapView = nil
    }

    private func apply(state: MarkerState, bitmapIcon: BitmapIcon, to marker: GMSMarker) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        marker.title = nil
        marker.isDraggable = state.draggable
        marker.isTappable = state.clickable
        marker.icon = bitmapIcon.bitmap
        marker.groundAnchor = bitmapIcon.anchor
        marker.position = CLLocationCoordinate2D(
            latitude: state.position.latitude,
            longitude: state.position.longitude
        )
        CATransaction.commit()
    }

    private func bouncePath(for mapView: GMSMapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
        let projection = mapView.projection
        let targetPoint = projection.point(for: target)
        let distance = targetPoint.y
        var point = targetPoint
        var path: [GeoPoint] = []

        // Match Android behavior: start from the top edge (y=0), same as Drop.
        let startPoint = CGPoint(x: targetPoint.x, y: 0)
        path.append(geoPoint(for: startPoint, projection: projection))

        var coefficient: CGFloat = 0.5
        point.y = distance * coefficient

        while coefficient > 0 {
            path.append(geoPoint(for: point, projection: projection))

            point.y = distance
            path.append(geoPoint(for: point, projection: projection))

            coefficient -= 0.15
            point.y = distance - distance * max(coefficient, 0)
        }
        path.append(GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0))
        return path
    }

    private func geoPoint(for point: CGPoint, projection: GMSProjection) -> GeoPoint {
        let coordinate = projection.coordinate(for: point)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }
}
