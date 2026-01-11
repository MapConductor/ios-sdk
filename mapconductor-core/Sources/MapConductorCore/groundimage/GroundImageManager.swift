import Foundation

public protocol GroundImageManagerProtocol {
    associatedtype ActualGroundImage

    func registerEntity(_ entity: GroundImageEntity<ActualGroundImage>)
    func removeEntity(_ id: String) -> GroundImageEntity<ActualGroundImage>?
    func getEntity(_ id: String) -> GroundImageEntity<ActualGroundImage>?
    func hasEntity(_ id: String) -> Bool
    func allEntities() -> [GroundImageEntity<ActualGroundImage>]
    func clear()
    func find(position: GeoPointProtocol) -> GroundImageEntity<ActualGroundImage>?
}

public final class GroundImageManager<ActualGroundImage>: GroundImageManagerProtocol {
    private var entities: [String: GroundImageEntity<ActualGroundImage>] = [:]
    private var destroyed = false
    private let lock = NSLock()
    private var registrationOrder: [String: Int] = [:]
    private var registrationCounter: Int = 0

    public init() {}

    public func registerEntity(_ entity: GroundImageEntity<ActualGroundImage>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        if registrationOrder[entity.state.id] == nil {
            registrationCounter += 1
            registrationOrder[entity.state.id] = registrationCounter
        }
        entities[entity.state.id] = entity
    }

    public func removeEntity(_ id: String) -> GroundImageEntity<ActualGroundImage>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        registrationOrder.removeValue(forKey: id)
        return entities.removeValue(forKey: id)
    }

    public func getEntity(_ id: String) -> GroundImageEntity<ActualGroundImage>? {
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

    public func allEntities() -> [GroundImageEntity<ActualGroundImage>] {
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
        registrationOrder.removeAll()
    }

    public func destroy() {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        destroyed = true
        entities.removeAll()
        registrationOrder.removeAll()
    }

    public var isDestroyed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return destroyed
    }

    public func find(position: GeoPointProtocol) -> GroundImageEntity<ActualGroundImage>? {
        let candidates = allEntities().filter { $0.state.bounds.contains(point: position) }
        guard !candidates.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }

        var best: GroundImageEntity<ActualGroundImage>?
        var bestOrder = Int.min
        for entity in candidates {
            let order = registrationOrder[entity.state.id] ?? 0
            if order > bestOrder {
                bestOrder = order
                best = entity
            }
        }
        return best
    }
}
