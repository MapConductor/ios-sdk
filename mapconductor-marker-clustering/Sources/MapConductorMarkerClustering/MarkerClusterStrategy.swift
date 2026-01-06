import Combine
import Foundation
import MapConductorCore

public final class MarkerClusterStrategy<ActualMarker>: AbstractMarkerRenderingStrategy<ActualMarker> {
    public static let DEFAULT_CLUSTER_RADIUS_PX: Double = 60.0
    public static let DEFAULT_MIN_CLUSTER_SIZE: Int = 2
    public static let DEFAULT_EXPAND_MARGIN: Double = 0.2
    public static let DEFAULT_TILE_SIZE: Double = 512.0

    private static let cameraDebounceMillis: Int = 100
    private static let maxDenseCells: Int = 4
    private static let maxDenseCandidates: Int = 50
    private static let degToRad: Double = Double.pi / 180.0
    private static let maxSinLat: Double = 0.9999

    public typealias ClusterIconProvider = (Int) -> MarkerIconProtocol
    public typealias ClusterIconProviderWithTurn = (Int, Int) -> MarkerIconProtocol

    public let clusterRadiusPx: Double
    public let minClusterSize: Int
    public let expandMargin: Double
    public let clusterIconProvider: ClusterIconProvider
    public let clusterIconProviderWithTurn: ClusterIconProviderWithTurn?
    public let includeTurnInClusterId: Bool
    public let tileSize: Double
    public let onClusterClick: ((MarkerCluster) -> Void)?

    private var sourceStates: [String: MarkerState] = [:]
    private var lastCameraPosition: MapCameraPosition?
    private var clusteringTurn: Int = 0
    private var lastZoomKey: Int?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceQueue = DispatchQueue(label: "MapConductorMarkerClusterStrategy")
    private var cameraUpdateToken: Int64 = 0
    private let tokenLock = NSLock()

    private let debugInfoSubject = CurrentValueSubject<[MarkerClusterDebugInfo], Never>([])
    public var debugInfoFlow: CurrentValueSubject<[MarkerClusterDebugInfo], Never> { debugInfoSubject }

    public init(
        clusterRadiusPx: Double = DEFAULT_CLUSTER_RADIUS_PX,
        minClusterSize: Int = DEFAULT_MIN_CLUSTER_SIZE,
        expandMargin: Double = DEFAULT_EXPAND_MARGIN,
        clusterIconProvider: @escaping ClusterIconProvider = MarkerClusterStrategy.defaultIconProvider,
        clusterIconProviderWithTurn: ClusterIconProviderWithTurn? = nil,
        includeTurnInClusterId: Bool = false,
        onClusterClick: ((MarkerCluster) -> Void)? = nil,
        tileSize: Double = DEFAULT_TILE_SIZE,
        semaphore: AsyncSemaphore = AsyncSemaphore(1)
    ) {
        self.clusterRadiusPx = clusterRadiusPx
        self.minClusterSize = minClusterSize
        self.expandMargin = expandMargin
        self.clusterIconProvider = clusterIconProvider
        self.clusterIconProviderWithTurn = clusterIconProviderWithTurn
        self.includeTurnInClusterId = includeTurnInClusterId
        self.onClusterClick = onClusterClick
        self.tileSize = tileSize
        super.init(semaphore: semaphore)
    }

    public override func clear() {
        sourceStates.removeAll()
        markerManager.clear()
        debugInfoSubject.value = []
    }

    public override func onAdd<Renderer: MarkerOverlayRendererProtocol>(
        data: [MarkerState],
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        updateSourceStates(data)
        guard let cameraPosition = lastCameraPosition else { return true }
        await renderClusters(
            cameraPosition: cameraPosition,
            viewport: viewport,
            renderer: renderer,
            token: currentToken()
        )
        return true
    }

    public override func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
        state: MarkerState,
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        sourceStates[state.id] = state
        guard let cameraPosition = lastCameraPosition else { return true }
        await renderClusters(
            cameraPosition: cameraPosition,
            viewport: viewport,
            renderer: renderer,
            token: currentToken()
        )
        return true
    }

    public override func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
        mapCameraPosition: MapCameraPosition,
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker {
        lastCameraPosition = mapCameraPosition
        let token = incrementToken()
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard token == self.currentToken() else { return }
            guard let viewport = mapCameraPosition.visibleRegion?.bounds else { return }
            Task {
                await self.renderClusters(
                    cameraPosition: mapCameraPosition,
                    viewport: viewport,
                    renderer: renderer,
                    token: token
                )
            }
        }
        debounceWorkItem = workItem
        debounceQueue.asyncAfter(
            deadline: .now() + .milliseconds(Self.cameraDebounceMillis),
            execute: workItem
        )
    }

    private func updateSourceStates(_ data: [MarkerState]) {
        let nextIds = Set(data.map { $0.id })
        let removedIds = Set(sourceStates.keys).subtracting(nextIds)
        removedIds.forEach { sourceStates.removeValue(forKey: $0) }
        data.forEach { state in
            sourceStates[state.id] = state
        }
    }

    private func renderClusters<Renderer: MarkerOverlayRendererProtocol>(
        cameraPosition: MapCameraPosition,
        viewport: GeoRectBounds,
        renderer: Renderer,
        token: Int64
    ) async where Renderer.ActualMarker == ActualMarker {
        await semaphore.withPermit {
            if token != currentToken() { return }
            let expandedBounds = expandBounds(bounds: viewport, margin: expandMargin)
            let zoom = cameraPosition.zoom
            let turn = updateClusteringTurn(zoom: zoom)
            var clustered: [ClusterCell: [MarkerState]] = [:]
            var debugInfos: [MarkerClusterDebugInfo] = []

            for state in sourceStates.values {
                if token != currentToken() { return }
                if !expandedBounds.contains(point: state.position) { continue }
                let (x, y) = projectToPixel(position: state.position, zoom: zoom, tileSize: tileSize)
                let cell = ClusterCell(
                    x: Int(floor(x / clusterRadiusPx)),
                    y: Int(floor(y / clusterRadiusPx))
                )
                clustered[cell, default: []].append(state)
            }

            let candidates = clustered.keys.sorted { lhs, rhs in
                if lhs.x == rhs.x { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }.compactMap { cell -> ClusterCandidate? in
                guard let members = clustered[cell], let center = members.first?.position else { return nil }
                return ClusterCandidate(
                    center: GeoPoint.from(position: center),
                    members: members
                )
            }

            let mergedClusters = mergeClusters(candidates: candidates, zoom: zoom)
            var desiredStates: [MarkerState] = []

            for merged in mergedClusters {
                if token != currentToken() { return }
                if merged.members.count >= minClusterSize {
                    let center = merged.center
                    let (cx, cy) = projectToPixel(position: center, zoom: zoom, tileSize: tileSize)
                    let cell = ClusterCell(
                        x: Int(floor(cx / clusterRadiusPx)),
                        y: Int(floor(cy / clusterRadiusPx))
                    )
                    let clusterId = buildClusterId(cell: cell, zoom: zoom, turn: turn)
                    let radiusMeters = calculateClusterRadiusMeters(center: center, members: merged.members)
                    let cluster = MarkerCluster(
                        count: merged.members.count,
                        markerIds: merged.members.map { $0.id }
                    )
                    debugInfos.append(
                        MarkerClusterDebugInfo(
                            id: clusterId,
                            center: center,
                            radiusMeters: radiusMeters,
                            count: merged.members.count
                        )
                    )
                    let icon =
                        clusterIconProviderWithTurn?(merged.members.count, turn) ??
                        clusterIconProvider(merged.members.count)
                    let clusterState = MarkerState(
                        position: center,
                        id: clusterId,
                        extra: cluster,
                        icon: icon,
                        animation: nil,
                        clickable: onClusterClick != nil,
                        draggable: false,
                        onClick: onClusterClick != nil ? { [weak self] _ in
                            guard let self else { return }
                            self.onClusterClick?(cluster)
                        } : nil,
                        onDragStart: nil,
                        onDrag: nil,
                        onDragEnd: nil,
                        onAnimateStart: nil,
                        onAnimateEnd: nil
                    )
                    desiredStates.append(clusterState)
                } else {
                    desiredStates.append(contentsOf: merged.members)
                }
            }

            if token != currentToken() { return }
            debugInfoSubject.value = debugInfos
            await updateRenderedMarkers(desiredStates: desiredStates, renderer: renderer)
        }
    }

    private func updateRenderedMarkers<Renderer: MarkerOverlayRendererProtocol>(
        desiredStates: [MarkerState],
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker {
        let desiredById = Dictionary(uniqueKeysWithValues: desiredStates.map { ($0.id, $0) })
        let existing = markerManager.allEntities()
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.state.id, $0) })

        let removeIds = Set(existingById.keys).subtracting(desiredById.keys)
        let addStates = desiredById.filter { existingById[$0.key] == nil }.map { $0.value }
        let updateStates = desiredById.filter { existingById[$0.key] != nil }.map { $0.value }

        let removedEntities = removeIds.compactMap { markerManager.getEntity($0) }
        if !removedEntities.isEmpty {
            await renderer.onRemove(data: removedEntities)
            removeIds.forEach { _ = markerManager.removeEntity($0) }
        }

        if !addStates.isEmpty {
            let addParams = addStates.map { state in
                MarkerOverlayAddParams(
                    state: state,
                    bitmapIcon: state.icon?.toBitmapIcon() ?? defaultMarkerIcon
                )
            }
            let actualMarkers = await renderer.onAdd(data: addParams)
            for (index, actualMarker) in actualMarkers.enumerated() {
                guard let actualMarker else { continue }
                let entity = MarkerEntity(
                    marker: actualMarker,
                    state: addParams[index].state,
                    visible: true,
                    isRendered: true
                )
                markerManager.registerEntity(entity)
            }
        }

        var changeParams: [MarkerOverlayChangeParams<ActualMarker>] = []
        var changeEntities: [MarkerEntity<ActualMarker>] = []

        for state in updateStates {
            guard let prev = existingById[state.id] else { continue }
            let nextEntity = MarkerEntity(
                marker: prev.marker,
                state: state,
                visible: true,
                isRendered: true
            )
            markerManager.registerEntity(nextEntity)

            if prev.fingerPrint == state.fingerPrint() {
                continue
            }

            let change = MarkerOverlayChangeParams(
                current: nextEntity,
                bitmapIcon: state.icon?.toBitmapIcon() ?? defaultMarkerIcon,
                prev: prev
            )
            changeParams.append(change)
            changeEntities.append(nextEntity)
        }

        if !changeParams.isEmpty {
            let actualMarkers = await renderer.onChange(data: changeParams)
            for (index, actualMarker) in actualMarkers.enumerated() {
                guard let actualMarker else { continue }
                let entity = MarkerEntity(
                    marker: actualMarker,
                    state: changeEntities[index].state,
                    visible: true,
                    isRendered: true
                )
                markerManager.registerEntity(entity)
            }
        }

        if !removedEntities.isEmpty || !addStates.isEmpty || !changeParams.isEmpty {
            await renderer.onPostProcess()
        }
    }

    private func buildClusterId(cell: ClusterCell, zoom: Double, turn: Int) -> String {
        if includeTurnInClusterId {
            return "cluster_\(Int(zoom.rounded()))_\(cell.x)_\(cell.y)_\(turn)"
        }
        return "cluster_\(Int(zoom.rounded()))_\(cell.x)_\(cell.y)"
    }

    private func projectToPixel(
        position: GeoPointProtocol,
        zoom: Double,
        tileSize: Double
    ) -> (Double, Double) {
        let scale = tileSize * pow(2.0, zoom)
        let sinLat = sin(position.latitude * Self.degToRad)
        let clamped = min(max(sinLat, -Self.maxSinLat), Self.maxSinLat)
        let x = (position.longitude + 180.0) / 360.0 * scale
        let y = (0.5 - log((1.0 + clamped) / (1.0 - clamped)) / (4.0 * Double.pi)) * scale
        return (x, y)
    }

    private func updateClusteringTurn(zoom: Double) -> Int {
        let zoomKey = Int((zoom * 100.0).rounded())
        if lastZoomKey == nil {
            clusteringTurn = 1
            lastZoomKey = zoomKey
            return clusteringTurn
        }
        if lastZoomKey != zoomKey {
            clusteringTurn += 1
            lastZoomKey = zoomKey
        }
        return clusteringTurn
    }

    private func metersPerPixel(position: GeoPointProtocol, zoom: Double, tileSize: Double) -> Double {
        let scale = tileSize * pow(2.0, zoom)
        let latitudeRadians = position.latitude * Self.degToRad
        return (Earth.circumferenceMeters * cos(latitudeRadians)) / scale
    }

    private func mergeClusters(candidates: [ClusterCandidate], zoom: Double) -> [MergedCluster] {
        guard !candidates.isEmpty else { return [] }
        var parent = Array(0..<candidates.count)

        func find(_ index: Int) -> Int {
            var i = index
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }

        func union(_ a: Int, _ b: Int) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB {
                parent[rootB] = rootA
            }
        }

        for i in 0..<candidates.count {
            let centerA = candidates[i].center
            let metersPerPixelA = metersPerPixel(position: centerA, zoom: zoom, tileSize: tileSize)
            for j in (i + 1)..<candidates.count {
                let centerB = candidates[j].center
                let metersPerPixelB = metersPerPixel(position: centerB, zoom: zoom, tileSize: tileSize)
                let thresholdMeters = clusterRadiusPx * max(metersPerPixelA, metersPerPixelB)
                let distanceMeters = Spherical.computeDistanceBetween(centerA, centerB)
                if distanceMeters <= thresholdMeters {
                    union(i, j)
                }
            }
        }

        var mergedMap: [Int: [ClusterCandidate]] = [:]
        for (index, candidate) in candidates.enumerated() {
            let root = find(index)
            mergedMap[root, default: []].append(candidate)
        }

        return mergedMap.values.map { group in
            var members: [MarkerState] = []
            group.forEach { candidate in
                members.append(contentsOf: candidate.members)
            }
            let center = selectDenseCenter(members: members, zoom: zoom)
            return MergedCluster(center: center, members: members)
        }
    }

    private func selectDenseCenter(members: [MarkerState], zoom: Double) -> GeoPoint {
        guard !members.isEmpty else { return GeoPoint(latitude: 0.0, longitude: 0.0) }
        if members.count == 1 {
            return GeoPoint.from(position: members[0].position)
        }

        let points = members.map { member -> PixelPoint in
            let (x, y) = projectToPixel(position: member.position, zoom: zoom, tileSize: tileSize)
            return PixelPoint(member: member, x: x, y: y)
        }
        let cellSize = clusterRadiusPx
        var cellMap: [CellKey: [PixelPoint]] = [:]
        for point in points {
            let key = CellKey(
                x: Int(floor(point.x / cellSize)),
                y: Int(floor(point.y / cellSize))
            )
            cellMap[key, default: []].append(point)
        }

        let sortedCells = cellMap.sorted { $0.value.count > $1.value.count }
        let candidates = sortedCells
            .prefix(Self.maxDenseCells)
            .flatMap { $0.value }
            .prefix(Self.maxDenseCandidates)

        let radiusSq = cellSize * cellSize
        var bestPoint = candidates.first ?? points[0]
        var bestNeighborCount = -1
        var bestTotalDistance = Double.greatestFiniteMagnitude

        for candidate in candidates {
            var neighborCount = 0
            var totalDistance = 0.0
            for dx in -1...1 {
                for dy in -1...1 {
                    let key = CellKey(
                        x: Int(floor(candidate.x / cellSize)) + dx,
                        y: Int(floor(candidate.y / cellSize)) + dy
                    )
                    let neighbors = cellMap[key] ?? []
                    for other in neighbors {
                        let dxp = candidate.x - other.x
                        let dyp = candidate.y - other.y
                        let distSq = dxp * dxp + dyp * dyp
                        if distSq <= radiusSq {
                            neighborCount += 1
                            totalDistance += sqrt(distSq)
                        }
                    }
                }
            }
            if neighborCount > bestNeighborCount ||
                (neighborCount == bestNeighborCount && totalDistance < bestTotalDistance) {
                bestNeighborCount = neighborCount
                bestTotalDistance = totalDistance
                bestPoint = candidate
            }
        }

        return GeoPoint.from(position: bestPoint.member.position)
    }

    private func calculateClusterRadiusMeters(center: GeoPoint, members: [MarkerState]) -> Double {
        var maxDistance = 0.0
        for state in members {
            let distance = Spherical.computeDistanceBetween(center, state.position)
            if distance > maxDistance {
                maxDistance = distance
            }
        }
        return maxDistance
    }

    private func incrementToken() -> Int64 {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cameraUpdateToken += 1
        return cameraUpdateToken
    }

    private func currentToken() -> Int64 {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        return cameraUpdateToken
    }

    public static let defaultIconProvider: ClusterIconProvider = { count in
        DefaultMarkerIcon(label: String(count))
    }

    private struct ClusterCandidate {
        let center: GeoPoint
        let members: [MarkerState]
    }

    private struct MergedCluster {
        let center: GeoPoint
        let members: [MarkerState]
    }

    private struct ClusterCell: Hashable {
        let x: Int
        let y: Int
    }

    private struct PixelPoint {
        let member: MarkerState
        let x: Double
        let y: Double
    }

    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }
}

private func expandBounds(bounds: GeoRectBounds, margin: Double) -> GeoRectBounds {
    if bounds.isEmpty { return bounds }
    guard let span = bounds.toSpan(), let center = bounds.center else { return bounds }

    let latMargin = span.latitude * margin / 2.0
    let lonMargin = span.longitude * margin / 2.0

    let expanded = GeoRectBounds()
    expanded.extend(
        point: GeoPoint(
            latitude: center.latitude - span.latitude / 2.0 - latMargin,
            longitude: center.longitude - span.longitude / 2.0 - lonMargin
        )
    )
    expanded.extend(
        point: GeoPoint(
            latitude: center.latitude + span.latitude / 2.0 + latMargin,
            longitude: center.longitude + span.longitude / 2.0 + lonMargin
        )
    )
    return expanded
}

private enum Earth {
    static let radiusMeters: Double = 6371009.0
    static let circumferenceMeters: Double = 2.0 * Double.pi * radiusMeters
}

private enum Spherical {
    static func computeDistanceBetween(_ a: GeoPointProtocol, _ b: GeoPointProtocol) -> Double {
        let lat1 = a.latitude * Double.pi / 180.0
        let lat2 = b.latitude * Double.pi / 180.0
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * Double.pi / 180.0

        let sinDLat = sin(dLat / 2.0)
        let sinDLon = sin(dLon / 2.0)
        let h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon
        return 2.0 * Earth.radiusMeters * asin(min(1.0, sqrt(h)))
    }
}
