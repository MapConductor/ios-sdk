import CoreGraphics
import CoreLocation
import Foundation
import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibreMarkerOverlayRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = MLNPointFeature

    enum Prop {
        static let markerId = "marker_id"
        static let iconId = "icon_id"
        static let iconAnchor = "icon-offset"
        static let defaultMarkerId = "default"
    }

    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    let markerLayer: MarkerLayer
    private let markerManager: MarkerManager<MLNPointFeature>
    private let defaultMarkerIcon: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    private var iconNameByMarkerId: [String: String] = [:]
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]

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
        MCLog.marker("MapLibreMarkerOverlayRenderer.onStyleLoaded")
        Task { await onPostProcess() }
    }

    func unbind() {
        if let style {
            markerLayer.remove(from: style)
        }
        style = nil
        mapView = nil
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        iconNameByMarkerId.removeAll()
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [MLNPointFeature?] {
        guard let style else { return [] }
        ensureDefaultIcon(style: style)
        MCLog.marker("MapLibreMarkerOverlayRenderer.onAdd count=\(data.count)")

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
                Prop.iconAnchor: iconOffset(defaultMarkerIcon)
            ]

            if state.icon != nil {
                let iconName = iconName(for: state.id)
                setImage(params.bitmapIcon.bitmap, name: iconName, style: style)
                attributes[Prop.iconId] = iconName
                attributes[Prop.iconAnchor] = iconOffset(params.bitmapIcon)
            }

            feature.attributes = attributes
            return feature
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<MLNPointFeature>]) async -> [MLNPointFeature?] {
        guard let style else { return [] }
        ensureDefaultIcon(style: style)
        if !data.isEmpty { MCLog.marker("MapLibreMarkerOverlayRenderer.onChange count=\(data.count)") }

        return data.map { params in
            guard let feature = params.prev.marker else { return nil }
            let state = params.current.state
            feature.coordinate = CLLocationCoordinate2D(
                latitude: state.position.latitude,
                longitude: state.position.longitude
            )

            var attributes = feature.attributes
            attributes[Prop.markerId] = state.id

            if state.icon == nil {
                attributes[Prop.iconId] = Prop.defaultMarkerId
                attributes[Prop.iconAnchor] = iconOffset(defaultMarkerIcon)
            } else {
                let iconName = iconName(for: state.id)
                setImage(params.bitmapIcon.bitmap, name: iconName, style: style)
                attributes[Prop.iconId] = iconName
                attributes[Prop.iconAnchor] = iconOffset(params.bitmapIcon)
            }

            feature.attributes = attributes
            return feature
        }
    }

    func onRemove(data: [MarkerEntity<MLNPointFeature>]) async {
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
        }
    }

    func onAnimate(entity: MarkerEntity<MLNPointFeature>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let mapView, let marker = entity.marker else { return }
        guard let animation = entity.state.getAnimation() else { return }

        MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate start id=\(entity.state.id) anim=\(animation) bounds=\(String(describing: mapView.bounds))")
        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=windowOrBounds")
            await deferAnimate(entity: entity)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        let targetPoint = mapView.convert(target, toPointTo: mapView)
        let startPoint = CGPoint(x: targetPoint.x, y: 0)
        let startCoord = mapView.convert(startPoint, toCoordinateFrom: mapView)
        let startBackPoint = mapView.convert(startCoord, toPointTo: mapView)

        MCLog.marker(
            "MapLibreMarkerOverlayRenderer.onAnimate id=\(entity.state.id) targetPoint=\(String(describing: targetPoint)) startPoint=\(String(describing: startPoint)) startBackPoint=\(String(describing: startBackPoint))"
        )

        if !targetPoint.x.isFinite || !targetPoint.y.isFinite || !startBackPoint.x.isFinite || !startBackPoint.y.isFinite {
            MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=nonFiniteProjection")
            await deferAnimate(entity: entity)
            return
        }

        let deltaX = abs(startBackPoint.x - targetPoint.x)
        let deltaY = abs(startBackPoint.y - 0.0)
        if deltaX > 4.0 || deltaY > 4.0 {
            MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=projectionMismatch dx=\(deltaX) dy=\(deltaY)")
            await deferAnimate(entity: entity)
            return
        }

        // If projection isn't ready yet, `startCoord` can collapse to the target coordinate,
        // resulting in a "no-op" animation on the very first request. Retry a few frames.
        if targetPoint.y > 1,
           abs(startCoord.latitude - target.latitude) < 1e-10,
           abs(startCoord.longitude - target.longitude) < 1e-10 {
            MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate defer id=\(entity.state.id) reason=projectionNotReady")
            await deferAnimate(entity: entity)
            return
        }

        let duration: CFTimeInterval = animation == .Drop ? 0.3 : 2.0

        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)
        let pathPoints = animation == .Bounce ? bouncePath(for: mapView, target: target) : nil

        marker.coordinate = startCoord
        await onPostProcess()

        animateStartListener?(entity.state)

        let runner = MarkerAnimationRunner(
            animation: animation,
            duration: duration,
            startPoint: startGeoPoint,
            targetPoint: targetGeoPoint,
            pathPoints: pathPoints,
            onUpdate: { [weak self] point in
                marker.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                Task { await self?.onPostProcess() }
            },
            onCompletion: { [weak self] in
                marker.coordinate = target
                entity.state.animate(nil)
                self?.markerAnimationRunners[entity.state.id] = nil
                MCLog.marker("MapLibreMarkerOverlayRenderer.onAnimate end id=\(entity.state.id)")
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
        MCLog.marker("MapLibreMarkerOverlayRenderer.deferAnimate id=\(id) attempt=\(attempts)")
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            MCLog.marker("MapLibreMarkerOverlayRenderer.deferAnimate id=\(id) givingUp")
            return
        }
        try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame
        await onAnimate(entity: entity)
    }

    func onPostProcess() async {
        let features = markerManager.allEntities().compactMap { $0.marker }
        markerLayer.setFeatures(features)
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
        let resolved = image.withRenderingMode(.alwaysOriginal)
        style.setImage(resolved, forName: name)
    }

    private func iconOffset(_ icon: BitmapIcon) -> [NSNumber] {
        // MapLibre style-spec: icon-offset is an array [x, y].
        // Use points here (UIImage.size is in points), matching Android's px/density conversion.
        let dx = -(icon.size.width * icon.anchor.x)
        let dy = -(icon.size.height * icon.anchor.y)
        return [NSNumber(value: Double(dx)), NSNumber(value: Double(dy))]
    }

    private func bouncePath(for mapView: MLNMapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
        let targetPoint = mapView.convert(target, toPointTo: mapView)
        let distance = targetPoint.y
        var point = targetPoint
        var path: [GeoPoint] = []

        // Match Android behavior: start from the top edge (y=0), same as Drop.
        let startPoint = CGPoint(x: targetPoint.x, y: 0)
        path.append(geoPoint(for: startPoint, mapView: mapView))

        var coefficient: CGFloat = 0.5
        point.y = distance * coefficient

        while coefficient > 0 {
            path.append(geoPoint(for: point, mapView: mapView))

            point.y = distance
            path.append(geoPoint(for: point, mapView: mapView))

            coefficient -= 0.15
            point.y = distance - distance * max(coefficient, 0)
        }
        path.append(GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0))
        return path
    }

    private func geoPoint(for point: CGPoint, mapView: MLNMapView) -> GeoPoint {
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }
}
