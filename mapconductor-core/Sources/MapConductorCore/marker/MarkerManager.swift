import Foundation
public final class MarkerManager<ActualMarker> {
    private var entities: [String: MarkerEntity<ActualMarker>] = [:]
    private var destroyed = false
    private let lock = NSLock()

    public init() {}

    public func getEntity(_ id: String) -> MarkerEntity<ActualMarker>? {
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

    @discardableResult
    public func removeEntity(_ id: String) -> MarkerEntity<ActualMarker>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities.removeValue(forKey: id)
    }

    public func registerEntity(_ entity: MarkerEntity<ActualMarker>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func updateEntity(_ entity: MarkerEntity<ActualMarker>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func allEntities() -> [MarkerEntity<ActualMarker>] {
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

    public static func defaultManager() -> MarkerManager<ActualMarker> {
        MarkerManager<ActualMarker>()
    }
}
