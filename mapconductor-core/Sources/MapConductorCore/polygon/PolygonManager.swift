import Foundation

public protocol PolygonManagerProtocol {
    associatedtype ActualPolygon

    func registerEntity(_ entity: PolygonEntity<ActualPolygon>)
    func removeEntity(_ id: String) -> PolygonEntity<ActualPolygon>?
    func getEntity(_ id: String) -> PolygonEntity<ActualPolygon>?
    func hasEntity(_ id: String) -> Bool
    func allEntities() -> [PolygonEntity<ActualPolygon>]
    func clear()
    func find(position: GeoPointProtocol) -> PolygonEntity<ActualPolygon>?
}

public final class PolygonManager<ActualPolygon>: PolygonManagerProtocol {
    private var entities: [String: PolygonEntity<ActualPolygon>] = [:]
    private var destroyed = false
    private let lock = NSLock()

    public init() {}

    public func registerEntity(_ entity: PolygonEntity<ActualPolygon>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func removeEntity(_ id: String) -> PolygonEntity<ActualPolygon>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities.removeValue(forKey: id)
    }

    public func getEntity(_ id: String) -> PolygonEntity<ActualPolygon>? {
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

    public func allEntities() -> [PolygonEntity<ActualPolygon>] {
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

    public func find(position: GeoPointProtocol) -> PolygonEntity<ActualPolygon>? {
        let testX = normalizeLng(position.longitude)
        let testY = position.latitude

        let sorted = allEntities().sorted { $0.state.zIndex > $1.state.zIndex }
        for entity in sorted {
            let state = entity.state
            let basePoints = state.points
            if basePoints.count < 3 { continue }

            let ring: [GeoPointProtocol]
            if state.geodesic {
                ring = createInterpolatePoints(basePoints)
            } else {
                ring = basePoints
            }

            guard let first = ring.first else { continue }
            let last = ring.last
            let isClosed = last.map { GeoPoint.from(position: first) == GeoPoint.from(position: $0) } ?? false
            let closedRing = isClosed ? ring : (ring + [first])
            if pointInPolygonWindingNumber(testX: testX, testY: testY, ring: closedRing) {
                return entity
            }
        }

        return nil
    }

    private func pointInPolygonWindingNumber(
        testX: Double,
        testY: Double,
        ring: [GeoPointProtocol]
    ) -> Bool {
        if ring.count < 3 { return false }

        let unwrapped = unwrapLongitudesAround(points: ring, refLng: testX)

        var minY = Double.infinity
        var maxY = -Double.infinity
        var minX = Double.infinity
        var maxX = -Double.infinity

        for p in unwrapped {
            minY = min(minY, p.1)
            maxY = max(maxY, p.1)
            minX = min(minX, p.0)
            maxX = max(maxX, p.0)
        }

        if testY < minY || testY > maxY || testX < minX - 1.0 || testX > maxX + 1.0 {
            return false
        }

        let eps = 1e-6
        var wn = 0

        var i = 0
        while i < unwrapped.count - 1 {
            let ax = unwrapped[i].0
            let ay = unwrapped[i].1
            let bx = unwrapped[i + 1].0
            let by = unwrapped[i + 1].1

            if pointOnSegment(px: testX, py: testY, ax: ax, ay: ay, bx: bx, by: by, eps: eps) {
                return true
            }

            if ay <= testY {
                if by > testY && isLeft(ax: ax, ay: ay, bx: bx, by: by, px: testX, py: testY) > 0 {
                    wn += 1
                }
            } else {
                if by <= testY && isLeft(ax: ax, ay: ay, bx: bx, by: by, px: testX, py: testY) < 0 {
                    wn -= 1
                }
            }

            i += 1
        }

        return wn != 0
    }

    private func isLeft(ax: Double, ay: Double, bx: Double, by: Double, px: Double, py: Double) -> Double {
        (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    }

    private func pointOnSegment(
        px: Double,
        py: Double,
        ax: Double,
        ay: Double,
        bx: Double,
        by: Double,
        eps: Double
    ) -> Bool {
        let dx = bx - ax
        let dy = by - ay
        let cross = dx * (py - ay) - dy * (px - ax)
        let segLen = sqrt(dx * dx + dy * dy)
        if abs(cross) > eps * max(1.0, segLen) { return false }
        let dot = (px - ax) * (px - bx) + (py - ay) * (py - by)
        return dot <= eps * max(1.0, segLen)
    }

    private func unwrapLongitudesAround(points: [GeoPointProtocol], refLng: Double) -> [(Double, Double)] {
        if points.isEmpty { return [] }
        var result: [(Double, Double)] = []
        result.reserveCapacity(points.count)

        var prevX = Double.nan
        for p in points {
            var x = normalizeLng(p.longitude)
            let y = p.latitude
            if prevX.isNaN {
                let k = round((refLng - x) / 360.0)
                x += 360.0 * k
            } else {
                let delta = x - prevX
                if delta > 180.0 {
                    let k = floor((delta + 180.0) / 360.0)
                    x -= 360.0 * k
                } else if delta < -180.0 {
                    let k = floor((-delta + 180.0) / 360.0)
                    x += 360.0 * k
                }
            }
            result.append((x, y))
            prevX = x
        }

        return result
    }

    private func normalizeLng(_ lng: Double) -> Double {
        (((lng + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
    }
}
