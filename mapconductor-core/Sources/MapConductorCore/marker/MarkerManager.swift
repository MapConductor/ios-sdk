import Foundation
public struct MarkerManagerStats: Sendable, Hashable {
    public let entityCount: Int
    public let hasSpatialIndex: Bool
    public let spatialIndexInitialized: Bool
    public let estimatedMemoryKB: Int
}

public final class MarkerManager<ActualMarker> {
    private let geocell: HexGeocellProtocol

    private var entities: [String: MarkerEntity<ActualMarker>] = [:]
    private var cellRegistry: HexCellRegistry<ActualMarker>?
    private var destroyed = false
    private let lock = NSLock()

    public init(geocell: HexGeocellProtocol = HexGeocell.defaultGeocell()) {
        self.geocell = geocell
    }

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
        let removed = entities.removeValue(forKey: id)
        if let removed {
            cellRegistry?.removePoint(entity: removed)
        }
        return removed
    }

    public func registerEntity(_ entity: MarkerEntity<ActualMarker>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
        cellRegistry?.setPoint(entity: entity)
    }

    public func updateEntity(_ entity: MarkerEntity<ActualMarker>) {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities[entity.state.id] = entity
        cellRegistry?.setPoint(entity: entity)
    }

    public func metersPerPixel(
        position: GeoPointProtocol,
        zoom: Double,
        pixels: Double,
        tileSize: Int = 256
    ) -> Double {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return 0.0 }
        let pixelsAtZoom = Double(tileSize) * pow(2.0, zoom)
        return Earth.circumferenceMeters / pixelsAtZoom * cos(position.latitude * .pi / 180.0) * pixels
    }

    public func findNearest(position: GeoPointProtocol) -> MarkerEntity<ActualMarker>? {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return nil }

        if entities.count > 50 {
            let registry = ensureCellRegistryLocked()
            if let nearestCell = registry.findNearest(point: position),
               let ids = registry.getEntryIDsByHexCell(nearestCell) {
                return ids
                    .compactMap { entities[$0] }
                    .min(by: { lhs, rhs in
                        let dx1 = lhs.state.position.latitude - position.latitude
                        let dy1 = lhs.state.position.longitude - position.longitude
                        let dx2 = rhs.state.position.latitude - position.latitude
                        let dy2 = rhs.state.position.longitude - position.longitude
                        return dx1 * dx1 + dy1 * dy1 < dx2 * dx2 + dy2 * dy2
                    })
            }
            return bruteForceNearestLocked(position: position)
        }

        return bruteForceNearestLocked(position: position)
    }

    private func bruteForceNearestLocked(position: GeoPointProtocol) -> MarkerEntity<ActualMarker>? {
        entities.values.min { lhs, rhs in
            let dx1 = lhs.state.position.latitude - position.latitude
            let dy1 = lhs.state.position.longitude - position.longitude
            let dx2 = rhs.state.position.latitude - position.latitude
            let dy2 = rhs.state.position.longitude - position.longitude
            return dx1 * dx1 + dy1 * dy1 < dx2 * dx2 + dy2 * dy2
        }
    }

    public func findByIdPrefix(_ prefix: String) -> [HexCell] {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return [] }
        return cellRegistry?.findByIdPrefix(prefix) ?? []
    }

    private func ensureCellRegistryLocked() -> HexCellRegistry<ActualMarker> {
        if let cellRegistry { return cellRegistry }

        let newRegistry = HexCellRegistry<ActualMarker>(geocell: geocell, zoom: 20.0)
        for entity in entities.values {
            newRegistry.setPoint(entity: entity)
        }
        cellRegistry = newRegistry
        return newRegistry
    }

    public func allEntities() -> [MarkerEntity<ActualMarker>] {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return [] }
        return Array(entities.values)
    }

    public func findMarkersInBounds(_ bounds: GeoRectBounds) -> [MarkerEntity<ActualMarker>] {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return [] }
        if bounds.isEmpty { return [] }

        // For large datasets we still fall back to brute force until bounds queries are added to HexCellRegistry.
        if entities.count > 100 {
            _ = ensureCellRegistryLocked()
        }

        return entities.values.filter { entity in
            bounds.contains(point: entity.state.position)
        }
    }

    public func getMemoryStats() -> MarkerManagerStats {
        lock.lock()
        defer { lock.unlock() }
        if destroyed {
            return MarkerManagerStats(
                entityCount: 0,
                hasSpatialIndex: false,
                spatialIndexInitialized: false,
                estimatedMemoryKB: 0
            )
        }
        return MarkerManagerStats(
            entityCount: entities.count,
            hasSpatialIndex: cellRegistry != nil,
            spatialIndexInitialized: cellRegistry != nil,
            estimatedMemoryKB: Int(estimateMemoryUsageLocked() / 1024)
        )
    }

    private func estimateMemoryUsageLocked() -> Int64 {
        let entityMapOverhead = Int64(entities.count) * 64
        let entityObjects = Int64(entities.count) * 200
        let spatialIndexSize = cellRegistry == nil ? 0 : Int64(entities.count) * 100
        return entityMapOverhead + entityObjects + spatialIndexSize
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        entities.removeAll()
        cellRegistry?.clear()
    }

    public func destroy() {
        lock.lock()
        defer { lock.unlock() }
        if destroyed { return }
        destroyed = true
        entities.removeAll()
        cellRegistry?.clear()
        cellRegistry = nil
    }

    public var isDestroyed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return destroyed
    }

    public static func defaultManager() -> MarkerManager<ActualMarker> {
        MarkerManager<ActualMarker>()
    }

    public static func defaultManager(geocell: HexGeocellProtocol) -> MarkerManager<ActualMarker> {
        MarkerManager<ActualMarker>(geocell: geocell)
    }
}
