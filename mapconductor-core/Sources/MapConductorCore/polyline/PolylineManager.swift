import Foundation

public struct PolylineHitResult<ActualPolyline> {
    public let entity: PolylineEntity<ActualPolyline>
    public let closestPoint: GeoPointProtocol
}

private struct DistanceResult {
    let distance: Double
    let closestPoint: GeoPointProtocol
}

private enum PolylineDefaults {
    static let tapTolerance: Double = 14.0
}

public protocol PolylineManagerProtocol {
    associatedtype ActualPolyline

    func registerEntity(_ entity: PolylineEntity<ActualPolyline>)
    func removeEntity(_ id: String) -> PolylineEntity<ActualPolyline>?
    func getEntity(_ id: String) -> PolylineEntity<ActualPolyline>?
    func hasEntity(_ id: String) -> Bool
    func allEntities() -> [PolylineEntity<ActualPolyline>]
    func clear()

    func find(
        position: GeoPointProtocol,
        cameraPosition: MapCameraPosition?
    ) -> PolylineHitResult<ActualPolyline>?
}

public final class PolylineManager<ActualPolyline>: PolylineManagerProtocol {
    private var entities: [String: PolylineEntity<ActualPolyline>] = [:]
    private var destroyed = false
    private let lock = NSLock()

    public init() {}

    public func registerEntity(_ entity: PolylineEntity<ActualPolyline>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func removeEntity(_ id: String) -> PolylineEntity<ActualPolyline>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities.removeValue(forKey: id)
    }

    public func getEntity(_ id: String) -> PolylineEntity<ActualPolyline>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities[id]
    }

    public func hasEntity(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return false }
        return entities[id] != nil
    }

    public func allEntities() -> [PolylineEntity<ActualPolyline>] {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return [] }
        return Array(entities.values)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities.removeAll()
    }

    public func destroy() {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        destroyed = true
        entities.removeAll()
    }

    public var isDestroyed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return destroyed
    }

    public func find(
        position: GeoPointProtocol,
        cameraPosition: MapCameraPosition?
    ) -> PolylineHitResult<ActualPolyline>? {
        let visibleRegion = cameraPosition?.visibleRegion?.bounds
        let zoom = cameraPosition?.zoom ?? 0.0
        let threshold = calculateMetersPerPixel(latitude: position.latitude, zoom: zoom) * PolylineDefaults.tapTolerance

        var candidates: [(PolylineEntity<ActualPolyline>, GeoPointProtocol, Double)] = []

        for entity in allEntities() {
            let points = entity.state.points
            guard points.count >= 2 else { continue }

            for index in 0..<(points.count - 1) {
                let segmentBounds = GeoRectBounds()
                segmentBounds.extend(point: points[index])
                segmentBounds.extend(point: points[index + 1])

                if let visibleRegion, !visibleRegion.intersects(other: segmentBounds) {
                    continue
                }

                let hit: (GeoPointProtocol, Double)?
                if entity.state.geodesic {
                    hit = pointOnGeodesicSegmentOrNull(
                        from: points[index],
                        to: points[index + 1],
                        position: position,
                        thresholdMeters: threshold
                    )
                } else {
                    hit = isPointOnLinearLine(
                        from: points[index],
                        to: points[index + 1],
                        position: position,
                        thresholdMeters: threshold
                    )
                }

                if let hit {
                    candidates.append((entity, hit.0, hit.1))
                }
            }
        }

        guard let closest = candidates.min(by: { $0.2 < $1.2 }) else { return nil }
        return PolylineHitResult(entity: closest.0, closestPoint: closest.1)
    }
}
