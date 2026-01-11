import CoreGraphics
import Foundation

/// Thread-safe registry of hex cells with a lazy KD-tree spatial index.
public final class HexCellRegistry<ActualMarker> {
    private let geocell: HexGeocellProtocol
    private let zoom: Double

    private var kdTree: KDTree?
    private var allCells: [String: HexCell] = [:]
    private var entryIDsByCell: [String: Set<String>] = [:]
    private var allEntries: [String: String] = [:] // entityId -> cellId
    private var needsRebuild = false

    private let lock = NSLock()

    public init(geocell: HexGeocellProtocol, zoom: Double) {
        self.geocell = geocell
        self.zoom = zoom
    }

    /// Get the hex cell for an entity without registering it.
    public func getCell(entity: MarkerEntity<ActualMarker>) -> HexCell {
        let coord = geocell.latLngToHexCoord(position: entity.state.position, zoom: zoom)
        let centerLatLng = geocell.hexToLatLngCenter(coord: coord, latHint: entity.state.position.latitude, zoom: zoom)
        let centerXY = geocell.projection.project(centerLatLng)
        let cellId = geocell.hexToCellId(coord: coord, zoom: zoom)
        return HexCell(coord: coord, centerLatLng: centerLatLng, centerXY: centerXY, id: cellId)
    }

    /// Register or update an entity in the registry.
    @discardableResult
    public func setPoint(entity: MarkerEntity<ActualMarker>) -> HexCell {
        lock.lock()
        defer { lock.unlock() }

        let entityId = entity.state.id

        if let oldCellId = allEntries[entityId] {
            _ = removeFromCell(cellId: oldCellId, entityId: entityId)
        }

        let cell = getCell(entity: entity)
        let cellId = cell.id

        allCells[cellId] = cell
        allEntries[entityId] = cellId

        var entryIds = entryIDsByCell[cellId] ?? Set<String>()
        entryIds.insert(entityId)
        entryIDsByCell[cellId] = entryIds

        markDirty()
        return cell
    }

    public func contains(hexId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allCells[hexId] != nil
    }

    /// Remove an entity from the registry.
    @discardableResult
    public func removePoint(entity: MarkerEntity<ActualMarker>) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let entityId = entity.state.id
        guard let cellId = allEntries[entityId] else { return false }

        let removed = removeFromCell(cellId: cellId, entityId: entityId)
        if removed {
            allEntries.removeValue(forKey: entityId)
            markDirty()
        }
        return removed
    }

    private func removeFromCell(cellId: String, entityId: String) -> Bool {
        guard var entryIds = entryIDsByCell[cellId] else { return false }
        let removed = entryIds.remove(entityId) != nil

        if removed {
            if entryIds.isEmpty {
                allCells.removeValue(forKey: cellId)
                entryIDsByCell.removeValue(forKey: cellId)
            } else {
                entryIDsByCell[cellId] = entryIds
            }
        }
        return removed
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        allCells.removeAll()
        entryIDsByCell.removeAll()
        allEntries.removeAll()
        kdTree = nil
        needsRebuild = false
    }

    private func markDirty() {
        needsRebuild = true
    }

    private func rebuildIfNeeded() {
        if !needsRebuild { return }
        kdTree = allCells.isEmpty ? nil : KDTree(points: Array(allCells.values))
        needsRebuild = false
    }

    public func findNearest(point: GeoPointProtocol) -> HexCell? {
        lock.lock()
        defer { lock.unlock() }
        rebuildIfNeeded()
        return kdTree?.nearest(query: geocell.projection.project(point))
    }

    public func findNearestWithDistance(point: GeoPointProtocol) -> HexCellWithDistance? {
        lock.lock()
        defer { lock.unlock() }
        rebuildIfNeeded()
        return kdTree?.nearestWithDistance(query: geocell.projection.project(point))
    }

    public func findNearestKWithDistance(point: GeoPointProtocol, k: Int) -> [HexCellWithDistance] {
        lock.lock()
        defer { lock.unlock() }
        rebuildIfNeeded()
        return kdTree?.nearestKWithDistance(query: geocell.projection.project(point), k: k) ?? []
    }

    public func findWithinRadiusWithDistance(point: GeoPointProtocol, radius: Double) -> [HexCellWithDistance] {
        lock.lock()
        defer { lock.unlock() }
        rebuildIfNeeded()
        return kdTree?.withinRadiusWithDistance(query: geocell.projection.project(point), radius: radius) ?? []
    }

    public func all() -> [HexCell] {
        lock.lock()
        defer { lock.unlock() }
        return Array(allCells.values)
    }

    public func getEntryIDsByHexCell(_ hexCell: HexCell) -> Set<String>? {
        lock.lock()
        defer { lock.unlock() }
        return entryIDsByCell[hexCell.id]
    }

    /// Calculates meters corresponding to `pixels` at `position` / `zoom`.
    ///
    /// - Note: This assumes the projection uses meters (WebMercator EPSG:3857).
    public func metersPerPixel(
        position: GeoPointProtocol,
        zoom: Double,
        pixels: Double,
        tileSize: Int = 256
    ) -> Double {
        precondition(pixels > 0, "Pixels must be positive")
        precondition(tileSize > 0, "Tile size must be positive")

        let deltaLng = 360.0 * pixels / (Double(tileSize) * pow(2.0, zoom))

        var newLng = position.longitude + deltaLng
        if newLng > 180.0 { newLng -= 360.0 }
        if newLng < -180.0 { newLng += 360.0 }

        let p1 = geocell.projection.project(position)
        let p2 = geocell.projection.project(GeoPoint(latitude: position.latitude, longitude: newLng, altitude: position.altitude ?? 0.0))

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    public func findWithinPixelRadius(
        position: GeoPointProtocol,
        zoom: Double,
        pixels: Double,
        tileSize: Int = 256
    ) -> [HexCellWithDistance] {
        let meters = metersPerPixel(position: position, zoom: zoom, pixels: pixels, tileSize: tileSize)
        return findWithinRadiusWithDistance(point: position, radius: meters)
    }

    public func findByIdPrefix(_ prefix: String) -> [HexCell] {
        precondition(!prefix.isEmpty, "Prefix cannot be empty")
        lock.lock()
        defer { lock.unlock() }
        return allCells
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
    }

    public func getStats() -> RegistryStats {
        lock.lock()
        defer { lock.unlock() }
        return RegistryStats(
            totalCells: allCells.count,
            totalEntries: allEntries.count,
            kdTreeBuilt: kdTree != nil,
            needsRebuild: needsRebuild
        )
    }
}

public struct RegistryStats: Sendable, Hashable {
    public let totalCells: Int
    public let totalEntries: Int
    public let kdTreeBuilt: Bool
    public let needsRebuild: Bool
}

