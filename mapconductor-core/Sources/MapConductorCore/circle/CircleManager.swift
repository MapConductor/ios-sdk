import Foundation

public protocol CircleManagerProtocol {
    associatedtype ActualCircle

    func registerEntity(_ entity: CircleEntity<ActualCircle>)
    func removeEntity(_ id: String) -> CircleEntity<ActualCircle>?
    func getEntity(_ id: String) -> CircleEntity<ActualCircle>?
    func hasEntity(_ id: String) -> Bool
    func allEntities() -> [CircleEntity<ActualCircle>]
    func clear()
    func find(position: GeoPointProtocol) -> CircleEntity<ActualCircle>?
}

public final class CircleManager<ActualCircle>: CircleManagerProtocol {
    private var entities: [String: CircleEntity<ActualCircle>] = [:]
    private var destroyed = false
    private let lock = NSLock()

    public init() {}

    public func registerEntity(_ entity: CircleEntity<ActualCircle>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func removeEntity(_ id: String) -> CircleEntity<ActualCircle>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities.removeValue(forKey: id)
    }

    public func getEntity(_ id: String) -> CircleEntity<ActualCircle>? {
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

    public func allEntities() -> [CircleEntity<ActualCircle>] {
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

    public func find(position: GeoPointProtocol) -> CircleEntity<ActualCircle>? {
        let candidates = allEntities().filter { entity in
            let center = entity.state.center
            let distance = haversineDistance(from: center, to: position)
            return distance <= entity.state.radiusMeters && entity.state.clickable
        }

        guard !candidates.isEmpty else { return nil }

        var maxEntity = candidates[0]
        var maxZIndex = Int.min
        for entity in candidates {
            let zIndex = entity.state.zIndex ?? calculateZIndex(for: entity.state.center)
            if zIndex > maxZIndex {
                maxZIndex = zIndex
                maxEntity = entity
            }
        }
        return maxEntity
    }

    private func calculateZIndex(for point: GeoPointProtocol) -> Int {
        let value = (-point.latitude * 1_000_000.0 - point.longitude)
        return Int(value.rounded())
    }

    private func haversineDistance(from: GeoPointProtocol, to: GeoPointProtocol) -> Double {
        let lat1 = deg2rad(from.latitude)
        let lon1 = deg2rad(from.longitude)
        let lat2 = deg2rad(to.latitude)
        let lon2 = deg2rad(to.longitude)

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return 6_378_137.0 * c
    }

    private func deg2rad(_ deg: Double) -> Double {
        deg * Double.pi / 180.0
    }
}
