import CoreGraphics
import CoreLocation
import MapKit
import MapConductorCore

@MainActor
final class MapKitMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = MKPointAnnotation

    private static let maxConcurrentAnimations = 30
    private static let minAnimationUpdateInterval: CFTimeInterval = 1.0 / 4.0

    weak var mapView: MKMapView?
    private let markerManager: MarkerManager<MKPointAnnotation>
    private var markerAnnotationViews: [String: MKAnnotationView] = [:]
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]
    private var lastAnimationUpdateTimeById: [String: CFTimeInterval] = [:]
    private var lastChangeBatchTime: CFTimeInterval = 0
    private var pendingChangeParams: [MarkerOverlayChangeParams<MKPointAnnotation>] = []
    private var pendingChangeTask: Task<Void, Never>?

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(mapView: MKMapView?, markerManager: MarkerManager<MKPointAnnotation>) {
        self.mapView = mapView
        self.markerManager = markerManager
    }

    deinit {
        MCLog.marker("MapKitMarkerRenderer.deinit")
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        pendingChangeParams.removeAll()
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [MKPointAnnotation?] {
        guard let mapView else { return [] }
        MCLog.marker("MapKitMarkerRenderer.onAdd count=\(data.count)")
        return data.map { params in
            let annotation = MapConductorPointAnnotation(
                markerState: params.state,
                bitmapIcon: params.bitmapIcon
            )
            mapView.addAnnotation(annotation)
            return annotation
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<MKPointAnnotation>]) async -> [MKPointAnnotation?] {
        if !data.isEmpty { MCLog.marker("MapKitMarkerRenderer.onChange count=\(data.count)") }
        let now = CACurrentMediaTime()
        if now - lastChangeBatchTime < Self.minAnimationUpdateInterval {
            pendingChangeParams = data
            schedulePendingChanges(after: Self.minAnimationUpdateInterval - (now - lastChangeBatchTime))
            return data.map { $0.prev.marker }
        }
        lastChangeBatchTime = now
        return applyChangeParams(data)
    }

    func onRemove(data: [MarkerEntity<MKPointAnnotation>]) async {
        guard let mapView else { return }
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
            if let annotation = entity.marker {
                mapView.removeAnnotation(annotation)
            }
            markerAnnotationViews.removeValue(forKey: entity.state.id)
        }
    }

    func onAnimate(entity: MarkerEntity<MKPointAnnotation>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let animation = entity.state.getAnimation() else { return }

        switch animation {
        case .Drop:
            await animateMarkerDrop(entity: entity, duration: 0.3) // 300ms
        case .Bounce:
            await animateMarkerBounce(entity: entity, duration: 2.0)  // 2000ms
        }
    }

    private func animateMarkerDrop(entity: MarkerEntity<MKPointAnnotation>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Drop, duration: duration)
    }

    private func animateMarkerBounce(entity: MarkerEntity<MKPointAnnotation>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Bounce, duration: duration)
    }

    private func animateMarker(
        entity: MarkerEntity<MKPointAnnotation>,
        animation: MarkerAnimation,
        duration: CFTimeInterval
    ) async {
        guard let mapView, let annotation = entity.marker else { return }
        guard let annotationView = mapView.view(for: annotation) else {
            await deferAnimate(entity: entity)
            return
        }

        if markerAnimationRunners.count >= Self.maxConcurrentAnimations {
            applyImmediatePosition(for: entity, to: annotation)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )

        // Check if marker target is visible on screen
        let targetPoint = mapView.convert(target, toPointTo: mapView)
        if !mapView.bounds.contains(targetPoint) {
            applyImmediatePosition(for: entity, to: annotation)
            return
        }

        MCLog.marker("MapKitMarkerRenderer.onAnimate start id=\(entity.state.id) anim=\(animation) bounds=\(String(describing: mapView.bounds))")
        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            MCLog.marker("MapKitMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=windowOrBounds")
            await deferAnimate(entity: entity)
            return
        }

        let startPoint = CGPoint(x: targetPoint.x, y: Self.animationStartY(in: mapView.bounds))
        let startCoord = mapView.convert(startPoint, toCoordinateFrom: mapView)
        let startBackPoint = mapView.convert(startCoord, toPointTo: mapView)

        MCLog.marker(
            "MapKitMarkerRenderer.onAnimate id=\(entity.state.id) targetPoint=\(String(describing: targetPoint)) startPoint=\(String(describing: startPoint)) startBackPoint=\(String(describing: startBackPoint))"
        )

        if !targetPoint.x.isFinite || !targetPoint.y.isFinite || !startBackPoint.x.isFinite || !startBackPoint.y.isFinite {
            MCLog.marker("MapKitMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=nonFiniteProjection")
            await deferAnimate(entity: entity)
            return
        }

        let deltaX = abs(startBackPoint.x - targetPoint.x)
        let deltaY = abs(startBackPoint.y - startPoint.y)
        if deltaX > 4.0 || deltaY > 4.0 {
            MCLog.marker("MapKitMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionMismatch dx=\(deltaX) dy=\(deltaY)")
            await deferAnimate(entity: entity)
            return
        }

        if targetPoint.y > 1,
           abs(startCoord.latitude - target.latitude) < 1e-10,
           abs(startCoord.longitude - target.longitude) < 1e-10 {
            MCLog.marker("MapKitMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionNotReady")
            await deferAnimate(entity: entity)
            return
        }

        // Set initial position offscreen
        annotationView.alpha = 1
        annotation.coordinate = startCoord

        animateStartListener?(entity.state)

        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)
        let pathPoints = animation == .Bounce
            ? bouncePath(for: mapView, target: target)
            : MarkerAnimationRunner.makeLinearPath(start: startGeoPoint, target: targetGeoPoint)

        let runner = MarkerAnimationRunner(
            duration: duration,
            pathPoints: pathPoints,
            onUpdate: { [weak self] point in
                guard let self else { return }
                let now = CACurrentMediaTime()
                let lastUpdate = self.lastAnimationUpdateTimeById[entity.state.id] ?? 0
                if now - lastUpdate < Self.minAnimationUpdateInterval {
                    return
                }
                self.lastAnimationUpdateTimeById[entity.state.id] = now
                annotation.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            },
            onCompletion: { [weak self] in
                annotation.coordinate = target
                entity.state.animate(nil)
                self?.markerAnimationRunners[entity.state.id] = nil
                self?.lastAnimationUpdateTimeById.removeValue(forKey: entity.state.id)
                MCLog.marker("MapKitMarkerRenderer.onAnimate end id=\(entity.state.id)")
                self?.animateEndListener?(entity.state)
            }
        )
        markerAnimationRunners[entity.state.id] = runner
        runner.start()
    }

    private func deferAnimate(entity: MarkerEntity<MKPointAnnotation>) async {
        let id = entity.state.id
        let attempts = (deferredAnimateAttemptsById[id] ?? 0) + 1
        deferredAnimateAttemptsById[id] = attempts
        MCLog.marker("MapKitMarkerRenderer.deferAnimate id=\(id) attempt=\(attempts)")
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            MCLog.marker("MapKitMarkerRenderer.deferAnimate id=\(id) givingUp")
            if let annotation = entity.marker {
                applyImmediatePosition(for: entity, to: annotation)
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
        for entity: MarkerEntity<MKPointAnnotation>,
        to annotation: MKPointAnnotation
    ) {
        entity.state.animate(nil)
        if let annotationView = mapView?.view(for: annotation) {
            annotationView.alpha = 1
        }
        annotation.coordinate = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        animateEndListener?(entity.state)
    }

    func onPostProcess() async {
        // No-op: MapKit applies changes directly on each annotation.
        _ = markerManager
    }

    func unbind() {
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        pendingChangeParams.removeAll()
        markerAnnotationViews.removeAll()
        mapView = nil
    }

    func configureAnnotationView(_ view: MKAnnotationView, for state: MarkerState, bitmapIcon: BitmapIcon) {
        view.image = bitmapIcon.bitmap
        view.isDraggable = state.draggable
        view.canShowCallout = false

        // Enable user interaction for dragging
        view.isEnabled = true

        // Store for later reference
        markerAnnotationViews[state.id] = view

        // Set anchor point based on icon anchor
        // MapKit's centerOffset is from the annotation coordinate to the view center
        // So y-axis needs to be inverted
        view.centerOffset = CGPoint(
            x: (bitmapIcon.anchor.x - 0.5) * bitmapIcon.bitmap.size.width,
            y: -(bitmapIcon.anchor.y - 0.5) * bitmapIcon.bitmap.size.height
        )

        // Hide initially if animation is specified
        if state.getAnimation() != nil && markerAnimationRunners[state.id] == nil {
            view.alpha = 0
        } else {
            view.alpha = 1
        }
    }

    private func applyChangeParams(
        _ data: [MarkerOverlayChangeParams<MKPointAnnotation>]
    ) -> [MKPointAnnotation?] {
        data.map { params in
            guard let annotation = params.prev.marker else { return nil }
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: params.current.state.position.latitude,
                longitude: params.current.state.position.longitude
            )

            if let annotationView = mapView?.view(for: annotation) {
                configureAnnotationView(annotationView, for: params.current.state, bitmapIcon: params.bitmapIcon)
            }

            return annotation
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

    private func bouncePath(for mapView: MKMapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
        let targetPoint = mapView.convert(target, toPointTo: mapView)
        let startY = Self.animationStartY(in: mapView.bounds)
        let startPoint = CGPoint(x: targetPoint.x, y: startY)
        let distance = targetPoint.y - startY
        var point = targetPoint
        var path: [GeoPoint] = []

        // Start from above the top edge (offscreen), same as Drop.
        path.append(geoPoint(for: startPoint, mapView: mapView))

        var coefficient: CGFloat = 0.5
        point.y = startY + distance * coefficient

        while coefficient > 0 {
            path.append(geoPoint(for: point, mapView: mapView))

            point.y = startY + distance
            path.append(geoPoint(for: point, mapView: mapView))

            coefficient -= 0.15
            point.y = startY + (distance - distance * max(coefficient, 0))
        }
        path.append(GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0))
        return path
    }

    private func geoPoint(for point: CGPoint, mapView: MKMapView) -> GeoPoint {
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }

    private static func animationStartY(in bounds: CGRect) -> CGFloat {
        -max(32.0, bounds.height * 0.2)
    }
}
