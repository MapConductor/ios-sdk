import CoreGraphics
import CoreLocation
import Foundation
import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibreMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = MLNPointFeature

    enum Prop {
        static let markerId = "marker_id"
        static let iconId = "icon_id"
        static let iconAnchor = "icon-offset"
        static let isHidden = "is_hidden"
        static let defaultMarkerId = "default"
    }

    private weak var mapView: MLNMapView?
    private weak var style: MLNStyle?

    let markerLayer: MarkerLayer
    private let markerManager: MarkerManager<MLNPointFeature>
    private let defaultMarkerIcon: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    private var iconNameByMarkerId: [String: String] = [:]
    private var lastBitmapIconByMarkerId: [String: BitmapIcon] = [:]
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]

    private let minPostProcessIntervalSeconds: CFTimeInterval = 1.0 / 8.0
    private var lastPostProcessTime: CFTimeInterval = 0
    private var postProcessScheduled: Bool = false
    private var postProcessPending: Bool = false
    private var postProcessTask: Task<Void, Never>?

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(
        mapView: MLNMapView?,
        markerManager: MarkerManager<MLNPointFeature>,
        markerLayer: MarkerLayer
    ) {
        self.mapView = mapView
        self.markerManager = markerManager
        self.markerLayer = markerLayer
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
        markerLayer.ensureAdded(to: style)
        ensureDefaultIcon(style: style)
        MCLog.marker("MapLibreMarkerRenderer.onStyleLoaded")
        Task { await onPostProcess() }
    }

    func unbind() {
        postProcessTask?.cancel()
        postProcessTask = nil
        postProcessPending = false
        postProcessScheduled = false
        if let style {
            markerLayer.remove(from: style)
        }
        style = nil
        mapView = nil
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        iconNameByMarkerId.removeAll()
        lastBitmapIconByMarkerId.removeAll()
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [MLNPointFeature?] {
        guard let style else { return [] }
        ensureDefaultIcon(style: style)
        MCLog.marker("MapLibreMarkerRenderer.onAdd count=\(data.count)")

        return data.map { params in
            let state = params.state
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(
                latitude: state.position.latitude,
                longitude: state.position.longitude
            )
            feature.identifier = "marker-\(state.id)" as NSString

            var attributes: [String: Any] = [
                Prop.markerId: state.id,
                Prop.iconId: Prop.defaultMarkerId,
                Prop.iconAnchor: iconOffset(defaultMarkerIcon),
                // Avoid a 1-frame "flash" at the target position when an animation is specified
                // at construction. Keep it hidden until `onAnimate` repositions it to the
                // offscreen start point.
                Prop.isHidden: NSNumber(value: state.getAnimation() != nil ? 1 : 0)
            ]

            if state.icon != nil {
                let iconName = iconName(for: state.id)
                if style.image(forName: iconName) == nil || lastBitmapIconByMarkerId[state.id] != params.bitmapIcon {
                    setImage(params.bitmapIcon.bitmap, name: iconName, style: style)
                }
                lastBitmapIconByMarkerId[state.id] = params.bitmapIcon
                attributes[Prop.iconId] = iconName
                attributes[Prop.iconAnchor] = iconOffset(params.bitmapIcon)
            } else {
                lastBitmapIconByMarkerId.removeValue(forKey: state.id)
            }

            feature.attributes = attributes
            return feature
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<MLNPointFeature>]) async -> [MLNPointFeature?] {
        guard let style else { return [] }
        ensureDefaultIcon(style: style)
        if !data.isEmpty { MCLog.marker("MapLibreMarkerRenderer.onChange count=\(data.count)") }

        return data.map { params in
            guard let feature = params.prev.marker else { return nil }
            let state = params.current.state
            feature.coordinate = CLLocationCoordinate2D(
                latitude: state.position.latitude,
                longitude: state.position.longitude
            )

            if state.getAnimation() != nil, markerAnimationRunners[state.id] == nil {
                var attributes = feature.attributes
                attributes[Prop.isHidden] = NSNumber(value: 1)
                feature.attributes = attributes
            }

            if state.icon == nil {
                if lastBitmapIconByMarkerId[state.id] != nil {
                    var attributes = feature.attributes
                    attributes[Prop.iconId] = Prop.defaultMarkerId
                    attributes[Prop.iconAnchor] = iconOffset(defaultMarkerIcon)
                    feature.attributes = attributes
                    lastBitmapIconByMarkerId.removeValue(forKey: state.id)
                }
            } else {
                let iconName = iconName(for: state.id)
                let iconChanged = lastBitmapIconByMarkerId[state.id] != params.bitmapIcon
                let imageMissing = style.image(forName: iconName) == nil
                if imageMissing || iconChanged {
                    setImage(params.bitmapIcon.bitmap, name: iconName, style: style)
                    var attributes = feature.attributes
                    attributes[Prop.iconId] = iconName
                    attributes[Prop.iconAnchor] = iconOffset(params.bitmapIcon)
                    feature.attributes = attributes
                    lastBitmapIconByMarkerId[state.id] = params.bitmapIcon
                } else if (feature.attribute(forKey: Prop.iconId) as? String) != iconName {
                    var attributes = feature.attributes
                    attributes[Prop.iconId] = iconName
                    feature.attributes = attributes
                }
            }

            return feature
        }
    }

    func onRemove(data: [MarkerEntity<MLNPointFeature>]) async {
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
            iconNameByMarkerId.removeValue(forKey: entity.state.id)
            lastBitmapIconByMarkerId.removeValue(forKey: entity.state.id)
        }
    }

    func onAnimate(entity: MarkerEntity<MLNPointFeature>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let animation = entity.state.getAnimation() else { return }

        switch animation {
        case .Drop:
            await animateMarkerDrop(entity: entity, duration: 0.3)  // 300ms
        case .Bounce:
            await animateMarkerBounce(entity: entity, duration: 2.0)  // 2000ms
        }
    }

    private func animateMarkerDrop(entity: MarkerEntity<MLNPointFeature>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Drop, duration: duration)
    }

    private func animateMarkerBounce(entity: MarkerEntity<MLNPointFeature>, duration: CFTimeInterval) async {
        await animateMarker(entity: entity, animation: .Bounce, duration: duration)
    }

    private func animateMarker(
        entity: MarkerEntity<MLNPointFeature>,
        animation: MarkerAnimation,
        duration: CFTimeInterval
    ) async {
        guard let mapView, let marker = entity.marker else { return }

        MCLog.marker("MapLibreMarkerRenderer.onAnimate start id=\(entity.state.id) anim=\(animation) bounds=\(String(describing: mapView.bounds))")
        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            MCLog.marker("MapLibreMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=windowOrBounds")
            await deferAnimate(entity: entity)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        let targetPoint = mapView.convert(target, toPointTo: mapView)
        let startPoint = CGPoint(x: targetPoint.x, y: Self.animationStartY(in: mapView.bounds))
        let startCoord = mapView.convert(startPoint, toCoordinateFrom: mapView)
        let startBackPoint = mapView.convert(startCoord, toPointTo: mapView)

        MCLog.marker(
            "MapLibreMarkerRenderer.onAnimate id=\(entity.state.id) targetPoint=\(String(describing: targetPoint)) startPoint=\(String(describing: startPoint)) startBackPoint=\(String(describing: startBackPoint))"
        )

        if !targetPoint.x.isFinite || !targetPoint.y.isFinite || !startBackPoint.x.isFinite || !startBackPoint.y.isFinite {
            MCLog.marker("MapLibreMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=nonFiniteProjection")
            await deferAnimate(entity: entity)
            return
        }

        let deltaX = abs(startBackPoint.x - targetPoint.x)
        let deltaY = abs(startBackPoint.y - startPoint.y)
        if deltaX > 4.0 || deltaY > 4.0 {
            MCLog.marker("MapLibreMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionMismatch dx=\(deltaX) dy=\(deltaY)")
            await deferAnimate(entity: entity)
            return
        }

        if targetPoint.y > 1,
           abs(startCoord.latitude - target.latitude) < 1e-10,
           abs(startCoord.longitude - target.longitude) < 1e-10 {
            MCLog.marker("MapLibreMarkerRenderer.onAnimate defer id=\(entity.state.id) reason=projectionNotReady")
            await deferAnimate(entity: entity)
            return
        }

        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)
        let pathPoints = animation == .Bounce
            ? bouncePath(for: mapView, target: target)
            : MarkerAnimationRunner.makeLinearPath(start: startGeoPoint, target: targetGeoPoint)

        var attributes = marker.attributes
        attributes[Prop.isHidden] = NSNumber(value: 0)
        marker.attributes = attributes
        marker.coordinate = startCoord
        await onPostProcess()

        animateStartListener?(entity.state)

        let runner = MarkerAnimationRunner(
            duration: duration,
            pathPoints: pathPoints,
            onUpdate: { [weak self] point in
                marker.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                Task { await self?.onPostProcess() }
            },
            onCompletion: { [weak self] in
                marker.coordinate = target
                entity.state.animate(nil)
                self?.markerAnimationRunners[entity.state.id] = nil
                MCLog.marker("MapLibreMarkerRenderer.onAnimate end id=\(entity.state.id)")
                self?.animateEndListener?(entity.state)
                Task { await self?.onPostProcess() }
            }
        )
        markerAnimationRunners[entity.state.id] = runner
        runner.start()
    }

    private func deferAnimate(entity: MarkerEntity<MLNPointFeature>) async {
        let id = entity.state.id
        let attempts = (deferredAnimateAttemptsById[id] ?? 0) + 1
        deferredAnimateAttemptsById[id] = attempts
        MCLog.marker("MapLibreMarkerRenderer.deferAnimate id=\(id) attempt=\(attempts)")
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            MCLog.marker("MapLibreMarkerRenderer.deferAnimate id=\(id) givingUp")
            if let marker = entity.marker {
                await applyImmediatePosition(for: entity, to: marker)
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
        for entity: MarkerEntity<MLNPointFeature>,
        to marker: MLNPointFeature
    ) async {
        entity.state.animate(nil)

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        marker.coordinate = target
        var attributes = marker.attributes
        attributes[Prop.isHidden] = NSNumber(value: 0)
        marker.attributes = attributes
        await onPostProcess()

        animateEndListener?(entity.state)
    }

    func onPostProcess() async {
        requestPostProcess()
    }

    func markerId(at point: CGPoint) -> String? {
        guard let mapView,
              let layer = markerLayer.layer else { return nil }
        let features = mapView.visibleFeatures(
            at: point,
            styleLayerIdentifiers: Set([layer.identifier])
        )
        guard let feature = features.first else { return nil }
        if let id = feature.attribute(forKey: Prop.markerId) as? String {
            return id
        }
        if let id = feature.identifier as? String {
            return id.replacingOccurrences(of: "marker-", with: "")
        }
        if let id = feature.identifier as? NSString {
            return String(id).replacingOccurrences(of: "marker-", with: "")
        }
        return nil
    }

    private func redrawAll() {
        let features = markerManager.allEntities().compactMap { $0.marker }
        markerLayer.setFeatures(features)
    }

    private func requestPostProcess() {
        postProcessPending = true
        guard !postProcessScheduled else { return }
        postProcessScheduled = true
        postProcessTask = Task { [weak self] in
            await self?.drainPostProcess()
        }
    }

    @MainActor
    private func drainPostProcess() async {
        while postProcessPending {
            postProcessPending = false
            if Task.isCancelled { break }

            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - lastPostProcessTime
            if elapsed < minPostProcessIntervalSeconds {
                let remaining = minPostProcessIntervalSeconds - elapsed
                let nanos = UInt64(max(0, remaining) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }

            if Task.isCancelled { break }

            lastPostProcessTime = CFAbsoluteTimeGetCurrent()
            guard let mapView, let currentStyle = mapView.style else {
                // Style can be temporarily nil during style changes or teardown.
                continue
            }

            // Re-attach layer/source if style changed underneath.
            if markerLayer.source == nil || markerLayer.layer == nil {
                markerLayer.ensureAdded(to: currentStyle)
                ensureDefaultIcon(style: currentStyle)
            }

            let features = markerManager.allEntities().compactMap { $0.marker }
            markerLayer.setFeatures(features)
        }
        postProcessScheduled = false
    }

    private func ensureDefaultIcon(style: MLNStyle) {
        if style.image(forName: Prop.defaultMarkerId) == nil {
            setImage(defaultMarkerIcon.bitmap, name: Prop.defaultMarkerId, style: style)
        }
    }

    private func iconName(for markerId: String) -> String {
        if let existing = iconNameByMarkerId[markerId] {
            return existing
        }
        let name = "marker-icon-\(markerId)"
        iconNameByMarkerId[markerId] = name
        return name
    }

    private func setImage(_ image: UIImage, name: String, style: MLNStyle) {
        // MapLibre treats style images as if they were @1x. To keep icons crisp on Retina
        // displays, register images with `scale = 1` (points == pixels), then rely on the
        // symbol layer's `iconScale` (1 / screenScale) to render at the intended size.
        let resolved = image.withRenderingMode(.alwaysOriginal)
        if let cgImage = resolved.cgImage {
            style.setImage(UIImage(cgImage: cgImage, scale: 1.0, orientation: resolved.imageOrientation), forName: name)
        } else {
            style.setImage(resolved, forName: name)
        }
    }

    private func iconOffset(_ icon: BitmapIcon) -> [NSNumber] {
        // MapLibre style values must be JSON-serializable. `CGVector` / `NSValue` cannot be
        // converted to `mbgl::Value`, so provide `[x, y]` (array of numbers) instead.
        //
        // The style images are registered as @1x (points == pixels), so multiply by screenScale.
        let s = UIScreen.main.scale
        let dx = -(icon.size.width * s * icon.anchor.x)
        let dy = -(icon.size.height * s * icon.anchor.y)
        return [NSNumber(value: Double(dx)), NSNumber(value: Double(dy))]
    }

    private func bouncePath(for mapView: MLNMapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
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

    private func geoPoint(for point: CGPoint, mapView: MLNMapView) -> GeoPoint {
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }

    private static func animationStartY(in bounds: CGRect) -> CGFloat {
        -max(32.0, bounds.height * 0.2)
    }
}
