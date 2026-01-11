import CoreGraphics
import CoreLocation
import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = GMSMarker

    private static let maxConcurrentAnimations = 30
    private static let minAnimationUpdateInterval: CFTimeInterval = 1.0 / 4.0

    weak var mapView: GMSMapView?
    private let markerManager: MarkerManager<GMSMarker>
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]
    private var lastAnimationUpdateTimeById: [String: CFTimeInterval] = [:]
    private var lastChangeBatchTime: CFTimeInterval = 0
    private var pendingChangeParams: [MarkerOverlayChangeParams<GMSMarker>] = []
    private var pendingChangeTask: Task<Void, Never>?

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(mapView: GMSMapView?, markerManager: MarkerManager<GMSMarker>) {
        self.mapView = mapView
        self.markerManager = markerManager
    }

    deinit {
        MCLog.marker("GoogleMapMarkerRenderer.deinit")
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        pendingChangeParams.removeAll()
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [GMSMarker?] {
        guard let mapView else { return [] }
        MCLog.marker("GoogleMapMarkerRenderer.onAdd count=\(data.count)")
        return data.map { params in
            let marker = GMSMarker()
            marker.map = mapView
            marker.userData = params.state.id
            apply(state: params.state, bitmapIcon: params.bitmapIcon, to: marker)
            return marker
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<GMSMarker>]) async -> [GMSMarker?] {
        if !data.isEmpty { MCLog.marker("GoogleMapMarkerRenderer.onChange count=\(data.count)") }
        let now = CACurrentMediaTime()
        if now - lastChangeBatchTime < Self.minAnimationUpdateInterval {
            pendingChangeParams = data
            schedulePendingChanges(after: Self.minAnimationUpdateInterval - (now - lastChangeBatchTime))
            return data.map { $0.prev.marker }
        }
        lastChangeBatchTime = now
        return applyChangeParams(data)
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
        guard let animation = entity.state.getAnimation() else { return }

        switch animation {
        case .Drop:
            await animateMarkerDrop(entity: entity, duration: 0.3) // 300ms
        case .Bounce:
            await animateMarkerBounce(entity: entity, duration: 2.0)  // 2000ms
        }
    }

    private func animateMarkerDrop(entity: MarkerEntity<GMSMarker>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Drop, duration: duration)
    }

    private func animateMarkerBounce(entity: MarkerEntity<GMSMarker>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Bounce, duration: duration)
    }

    private func animateMarker(
        entity: MarkerEntity<GMSMarker>,
        animation: MarkerAnimation,
        duration: CFTimeInterval
    ) async {
        guard let mapView, let marker = entity.marker else { return }

        if markerAnimationRunners.count >= Self.maxConcurrentAnimations {
            applyImmediatePosition(for: entity, to: marker)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )

        // Check if marker target is visible on screen
        let targetPoint = mapView.projection.point(for: target)
        if !mapView.bounds.contains(targetPoint) {
            applyImmediatePosition(for: entity, to: marker)
            return
        }

        MCLog.marker("GoogleMapMarkerRenderer.onAnimate start id=\(entity.state.id) anim=\(animation) bounds=\(String(describing: mapView.bounds))")
        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            MCLog.marker("GoogleMapMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=windowOrBounds")
            await deferAnimate(entity: entity)
            return
        }

        let startPoint = CGPoint(x: targetPoint.x, y: Self.animationStartY(in: mapView.bounds))
        let startCoord = mapView.projection.coordinate(for: startPoint)
        let startBackPoint = mapView.projection.point(for: startCoord)

        MCLog.marker(
            "GoogleMapMarkerRenderer.onAnimate id=\(entity.state.id) targetPoint=\(String(describing: targetPoint)) startPoint=\(String(describing: startPoint)) startBackPoint=\(String(describing: startBackPoint))"
        )

        if !targetPoint.x.isFinite || !targetPoint.y.isFinite || !startBackPoint.x.isFinite || !startBackPoint.y.isFinite {
            MCLog.marker("GoogleMapMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=nonFiniteProjection")
            await deferAnimate(entity: entity)
            return
        }

        let deltaX = abs(startBackPoint.x - targetPoint.x)
        let deltaY = abs(startBackPoint.y - startPoint.y)
        if deltaX > 4.0 || deltaY > 4.0 {
            MCLog.marker("GoogleMapMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionMismatch dx=\(deltaX) dy=\(deltaY)")
            await deferAnimate(entity: entity)
            return
        }

        if targetPoint.y > 1,
           abs(startCoord.latitude - target.latitude) < 1e-10,
           abs(startCoord.longitude - target.longitude) < 1e-10 {
            MCLog.marker("GoogleMapMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionNotReady")
            await deferAnimate(entity: entity)
            return
        }

        // Prevent implicit animations on map assignment / initial position.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        let oldMap = marker.map
        marker.map = nil
        marker.position = startCoord
        marker.opacity = 1
        marker.map = oldMap
        CATransaction.commit()

        animateStartListener?(entity.state)

        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)
        let pathPoints = animation == .Bounce
            ? bouncePath(for: mapView, target: target)
            : MarkerAnimationRunner.makeLinearPath(start: startGeoPoint, target: targetGeoPoint)

        let runner = MarkerAnimationRunner(
            duration: duration,
            pathPoints: pathPoints,
            onUpdate: { point in
                let now = CACurrentMediaTime()
                let lastUpdate = self.lastAnimationUpdateTimeById[entity.state.id] ?? 0
                if now - lastUpdate < Self.minAnimationUpdateInterval {
                    return
                }
                self.lastAnimationUpdateTimeById[entity.state.id] = now
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
                self?.lastAnimationUpdateTimeById.removeValue(forKey: entity.state.id)
                MCLog.marker("GoogleMapMarkerRenderer.onAnimate end id=\(entity.state.id)")
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
        MCLog.marker("GoogleMapMarkerRenderer.deferAnimate id=\(id) attempt=\(attempts)")
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            MCLog.marker("GoogleMapMarkerRenderer.deferAnimate id=\(id) givingUp")
            if let marker = entity.marker {
                applyImmediatePosition(for: entity, to: marker)
            } else {
                entity.state.animate(nil)
                animateEndListener?(entity.state)
            }
            return
        }
        try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame
        await onAnimate(entity: entity)
    }


    private func applyImmediatePosition(
        for entity: MarkerEntity<GMSMarker>,
        to marker: GMSMarker
    ) {
        entity.state.animate(nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        marker.opacity = 1
        marker.position = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        CATransaction.commit()
        animateEndListener?(entity.state)
    }

    func onPostProcess() async {
        // No-op: Google Maps applies changes directly on each marker.
        _ = markerManager
    }

    func unbind() {
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        pendingChangeParams.removeAll()
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
        // Avoid a 1-frame "flash" at the target position when an animation is specified at
        // construction (or during a state update). Keep it hidden until `onAnimate` repositions
        // it to the offscreen start point.
        marker.opacity = (state.getAnimation() != nil && markerAnimationRunners[state.id] == nil) ? 0 : 1
        marker.position = CLLocationCoordinate2D(
            latitude: state.position.latitude,
            longitude: state.position.longitude
        )
        CATransaction.commit()
    }

    private func applyChangeParams(
        _ data: [MarkerOverlayChangeParams<GMSMarker>]
    ) -> [GMSMarker?] {
        data.map { params in
            guard let marker = params.prev.marker else { return nil }
            apply(state: params.current.state, bitmapIcon: params.bitmapIcon, to: marker)
            return marker
        }
    }

    private func schedulePendingChanges(after delay: CFTimeInterval) {
        if pendingChangeTask != nil { return }
        pendingChangeTask = Task { [weak self] in
            let delayNanos = UInt64(max(0, delay) * 1_000_000_000)
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            await self?.flushPendingChanges()
        }
    }

    @MainActor
    private func flushPendingChanges() async {
        pendingChangeTask = nil
        guard !pendingChangeParams.isEmpty else { return }
        lastChangeBatchTime = CACurrentMediaTime()
        _ = applyChangeParams(pendingChangeParams)
        pendingChangeParams.removeAll()
    }

    private func bouncePath(for mapView: GMSMapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
        let projection = mapView.projection
        let targetPoint = projection.point(for: target)
        let startY = Self.animationStartY(in: mapView.bounds)
        let startPoint = CGPoint(x: targetPoint.x, y: startY)
        let distance = targetPoint.y - startY
        var point = targetPoint
        var path: [GeoPoint] = []

        // Start from above the top edge (offscreen), same as Drop.
        path.append(geoPoint(for: startPoint, projection: projection))

        var coefficient: CGFloat = 0.5
        point.y = startY + distance * coefficient

        while coefficient > 0 {
            path.append(geoPoint(for: point, projection: projection))

            point.y = startY + distance
            path.append(geoPoint(for: point, projection: projection))

            coefficient -= 0.15
            point.y = startY + (distance - distance * max(coefficient, 0))
        }
        path.append(GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0))
        return path
    }

    private func geoPoint(for point: CGPoint, projection: GMSProjection) -> GeoPoint {
        let coordinate = projection.coordinate(for: point)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }

    private static func animationStartY(in bounds: CGRect) -> CGFloat {
        -max(32.0, bounds.height * 0.2)
    }
}
