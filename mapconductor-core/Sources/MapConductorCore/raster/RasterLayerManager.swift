import Foundation

public protocol RasterLayerManagerProtocol {
    associatedtype ActualLayer

    func registerEntity(_ entity: RasterLayerEntity<ActualLayer>)
    func removeEntity(_ id: String) -> RasterLayerEntity<ActualLayer>?
    func getEntity(_ id: String) -> RasterLayerEntity<ActualLayer>?
    func hasEntity(_ id: String) -> Bool
    func allEntities() -> [RasterLayerEntity<ActualLayer>]
    func clear()
    func find(position: GeoPointProtocol) -> RasterLayerEntity<ActualLayer>?
}

public final class RasterLayerManager<ActualLayer>: RasterLayerManagerProtocol {
    private var entities: [String: RasterLayerEntity<ActualLayer>] = [:]
    private var destroyed = false
    private let lock = NSLock()

    public init() {}

    public func registerEntity(_ entity: RasterLayerEntity<ActualLayer>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
    }

    public func removeEntity(_ id: String) -> RasterLayerEntity<ActualLayer>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }
        return entities.removeValue(forKey: id)
    }

    public func getEntity(_ id: String) -> RasterLayerEntity<ActualLayer>? {
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

    public func allEntities() -> [RasterLayerEntity<ActualLayer>] {
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

    public func find(position: GeoPointProtocol) -> RasterLayerEntity<ActualLayer>? {
        nil
    }
}
