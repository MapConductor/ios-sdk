import Combine
import Foundation
import MapConductorCore

private let markerClusterDefaultClusterRadiusPx: Double = 60.0
private let markerClusterDefaultMinClusterSize: Int = 2
private let markerClusterDefaultExpandMargin: Double = 0.2
private let markerClusterDefaultTileSize: Double = 512.0
private let markerClusterDefaultZoomAnimationDurationMillis: Int = 200
public let markerClusterCameraDebounceMillis: Int = 100
private let markerClusterAnimationFrameMillis: Int = 16
private let markerClusterMaxDenseCells: Int = 4
private let markerClusterMaxDenseCandidates: Int = 50
private let markerClusterPanAnimationMinDistanceMeters: Double = 1.0
private let markerClusterCameraAngleEpsilon: Double = 1e-2
private let markerClusterDegToRad: Double = Double.pi / 180.0
private let markerClusterMaxSinLat: Double = 0.9999

public final class MarkerClusterStrategy<ActualMarker>: AbstractMarkerRenderingStrategy<ActualMarker> {
    public static var DEFAULT_CLUSTER_RADIUS_PX: Double { markerClusterDefaultClusterRadiusPx }
    public static var DEFAULT_MIN_CLUSTER_SIZE: Int { markerClusterDefaultMinClusterSize }
    public static var DEFAULT_EXPAND_MARGIN: Double { markerClusterDefaultExpandMargin }
    public static var DEFAULT_TILE_SIZE: Double { markerClusterDefaultTileSize }
    public static var DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS: Int { markerClusterDefaultZoomAnimationDurationMillis }

    private static var cameraDebounceMillis: Int { markerClusterCameraDebounceMillis }
    private static var animationFrameMillis: Int { markerClusterAnimationFrameMillis }
    private static var maxDenseCells: Int { markerClusterMaxDenseCells }
    private static var maxDenseCandidates: Int { markerClusterMaxDenseCandidates }
    private static var panAnimationMinDistanceMeters: Double { markerClusterPanAnimationMinDistanceMeters }
    private static var cameraAngleEpsilon: Double { markerClusterCameraAngleEpsilon }
    private static var degToRad: Double { markerClusterDegToRad }
    private static var maxSinLat: Double { markerClusterMaxSinLat }

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
    public let enableZoomAnimation: Bool
    public let enablePanAnimation: Bool
    public let zoomAnimationDurationMillis: Int
    public let cameraIdleDebounceMillis: Int

    private var sourceStates: [String: MarkerState] = [:]
    private var lastCameraPosition: MapCameraPosition?
    private var clusteringTurn: Int = 0
    private var lastZoomKey: Int?
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceQueue = DispatchQueue(label: "MapConductorMarkerClusterStrategy")
    private var cameraUpdateToken: Int64 = 0
    private let tokenLock = NSLock()
    private let renderQueue = DispatchQueue(label: "MapConductorMarkerClusterStrategy.render")
    private var pendingRenderRequest: RenderRequest?
    private var renderTask: Task<Void, Never>?
    private var lastViewport: GeoRectBounds?

    private let debugInfoSubject = CurrentValueSubject<[MarkerClusterDebugInfo], Never>([])
    public var debugInfoFlow: CurrentValueSubject<[MarkerClusterDebugInfo], Never> { debugInfoSubject }
    private var lastClusterMemberCenters: [String: GeoPoint] = [:]
    private var lastClusterPositions: [String: GeoPoint] = [:]
    private var lastRenderCameraPosition: MapCameraPosition?
    private var renderedMarkerEntities: [String: MarkerEntity<ActualMarker>] = [:]

    public init(
        clusterRadiusPx: Double = DEFAULT_CLUSTER_RADIUS_PX,
        minClusterSize: Int = DEFAULT_MIN_CLUSTER_SIZE,
        expandMargin: Double = DEFAULT_EXPAND_MARGIN,
        clusterIconProvider: @escaping ClusterIconProvider = MarkerClusterStrategy.defaultIconProvider,
        clusterIconProviderWithTurn: ClusterIconProviderWithTurn? = nil,
        includeTurnInClusterId: Bool = false,
        onClusterClick: ((MarkerCluster) -> Void)? = nil,
        enableZoomAnimation: Bool = false,
        enablePanAnimation: Bool = false,
        zoomAnimationDurationMillis: Int = DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS,
        cameraIdleDebounceMillis: Int = markerClusterCameraDebounceMillis,
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
        self.enableZoomAnimation = enableZoomAnimation
        self.enablePanAnimation = enablePanAnimation
        self.zoomAnimationDurationMillis = zoomAnimationDurationMillis
        self.cameraIdleDebounceMillis = cameraIdleDebounceMillis
        self.tileSize = tileSize
        super.init(semaphore: semaphore)
    }

    public override func clear() {
        sourceStates.removeAll()
        markerManager.clear()
        debugInfoSubject.value = []
        lastClusterMemberCenters = [:]
        lastClusterPositions = [:]
        lastRenderCameraPosition = nil
        renderedMarkerEntities.removeAll()
        lastZoomKey = nil
        clusteringTurn = 0
    }

    public override func onAdd<Renderer: MarkerOverlayRendererProtocol>(
        data: [MarkerState],
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        MCLog.marker("MarkerClusterStrategy.onAdd count=\(data.count)")
        lastViewport = viewport
        updateSourceStates(data)
        guard let cameraPosition = lastCameraPosition else { return true }
        await MainActor.run {
            enqueueRender(
                cameraPosition: cameraPosition,
                viewport: viewport,
                renderer: renderer,
                token: currentToken()
            )
        }
        return true
    }

    public override func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
        state: MarkerState,
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        MCLog.marker("MarkerClusterStrategy.onUpdate id=\(state.id)")
        sourceStates[state.id] = state
        lastViewport = viewport
        guard let cameraPosition = lastCameraPosition else { return true }
        await MainActor.run {
            enqueueRender(
                cameraPosition: cameraPosition,
                viewport: viewport,
                renderer: renderer,
                token: currentToken()
            )
        }
        return true
    }

    public override func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
        mapCameraPosition: MapCameraPosition,
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker {
        lastCameraPosition = mapCameraPosition
        MCLog.marker("MarkerClusterStrategy.onCameraChanged zoom=\(mapCameraPosition.zoom)")
        let token = incrementToken()
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard token == self.currentToken() else { return }
            let viewport =
                mapCameraPosition.visibleRegion?.bounds ??
                self.lastViewport
            guard let viewport else {
                MCLog.marker("MarkerClusterStrategy.onCameraChanged viewportMissing")
                return
            }
            self.lastViewport = viewport
            Task { @MainActor in
                self.enqueueRender(
                    cameraPosition: mapCameraPosition,
                    viewport: viewport,
                    renderer: renderer,
                    token: token
                )
            }
        }
        debounceWorkItem = workItem
        debounceQueue.asyncAfter(
            deadline: .now() + .milliseconds(cameraIdleDebounceMillis),
            execute: workItem
        )
    }

    @MainActor
    private func enqueueRender<Renderer: MarkerOverlayRendererProtocol>(
        cameraPosition: MapCameraPosition,
        viewport: GeoRectBounds,
        renderer: Renderer,
        token: Int64
    ) where Renderer.ActualMarker == ActualMarker {
        let anyRenderer = AnyMarkerOverlayRenderer(renderer)
        let request = RenderRequest(
            cameraPosition: cameraPosition,
            viewport: viewport,
            renderer: anyRenderer,
            token: token
        )
        renderQueue.sync {
            pendingRenderRequest = request
            MCLog.marker("MarkerClusterStrategy.enqueueRender token=\(token)")
            if renderTask == nil {
                renderTask = Task { await self.processRenderQueue() }
            }
        }
    }

    private func processRenderQueue() async {
        while true {
            let request: RenderRequest? = renderQueue.sync {
                let next = pendingRenderRequest
                pendingRenderRequest = nil
                return next
            }
            guard let request else {
                renderQueue.sync { renderTask = nil }
                return
            }
            MCLog.marker("MarkerClusterStrategy.processRenderQueue token=\(request.token)")
            await renderClusters(
                cameraPosition: request.cameraPosition,
                viewport: request.viewport,
                renderer: request.renderer,
                token: request.token
            )
        }
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
            let zoomChange = updateClusteringTurn(zoom: zoom)
            let turn = zoomChange.turn
            let zoomChanged = zoomChange.zoomChanged
            let cameraMoved = lastRenderCameraPosition.map { hasCameraMoved(previous: $0, current: cameraPosition) } ?? false
            let animateTransitions = (enableZoomAnimation && zoomChanged) || (enablePanAnimation && cameraMoved)
            MCLog.marker("MarkerClusterStrategy.renderClusters zoom=\(zoom) animate=\(animateTransitions)")
            var clustered: [ClusterCell: [MarkerState]] = [:]
            var debugInfos: [MarkerClusterDebugInfo] = []
            var clusterMemberCenters: [String: GeoPoint] = [:]
            var clusterPositions: [String: GeoPoint] = [:]

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
                    for member in merged.members {
                        clusterMemberCenters[member.id] = center
                    }
                    clusterPositions[clusterId] = center
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
            let previousClusterMemberCenters = lastClusterMemberCenters
            let previousClusterPositions = lastClusterPositions
            await updateRenderedMarkers(
                desiredStates: desiredStates,
                renderer: renderer,
                token: token,
                animateTransitions: animateTransitions,
                previousClusterMemberCenters: previousClusterMemberCenters,
                nextClusterMemberCenters: clusterMemberCenters,
                previousClusterPositions: previousClusterPositions,
                nextClusterPositions: clusterPositions
            )
            lastClusterMemberCenters = clusterMemberCenters
            lastClusterPositions = clusterPositions
            lastRenderCameraPosition = cameraPosition
        }
    }

    private func updateRenderedMarkers<Renderer: MarkerOverlayRendererProtocol>(
        desiredStates: [MarkerState],
        renderer: Renderer,
        token: Int64,
        animateTransitions: Bool,
        previousClusterMemberCenters: [String: GeoPoint],
        nextClusterMemberCenters: [String: GeoPoint],
        previousClusterPositions: [String: GeoPoint],
        nextClusterPositions: [String: GeoPoint]
    ) async where Renderer.ActualMarker == ActualMarker {
        let desiredById = Dictionary(uniqueKeysWithValues: desiredStates.map { ($0.id, $0) })
        let animateZoom = animateTransitions && zoomAnimationDurationMillis > 0
        let existing = markerManager.allEntities()
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.state.id, $0) })
        MCLog.marker("MarkerClusterStrategy.updateRenderedMarkers desired=\(desiredStates.count) existing=\(existing.count) animate=\(animateZoom)")

        if !animateZoom {
            let orphanedIds = Set(existingById.keys).subtracting(desiredById.keys)
            let orphanedEntitiesBeforeAnimation = orphanedIds.compactMap { renderedMarkerEntities[$0] }
            if !orphanedEntitiesBeforeAnimation.isEmpty {
                await renderer.onRemove(data: orphanedEntitiesBeforeAnimation)
                for entity in orphanedEntitiesBeforeAnimation {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                await renderer.onPostProcess()
            }
        }

        let existingAfterCleanup = markerManager.allEntities()
        let existingByIdAfterCleanup = Dictionary(uniqueKeysWithValues: existingAfterCleanup.map { ($0.state.id, $0) })

        let removeIds = Set(existingByIdAfterCleanup.keys).subtracting(desiredById.keys)
        let addStates = desiredById.filter { existingByIdAfterCleanup[$0.key] == nil }.map { $0.value }
        let updateStates = desiredById.filter { existingByIdAfterCleanup[$0.key] != nil }.map { $0.value }

        let animatedRemoveEntries: [AnimatedRemove<ActualMarker>] =
            if animateZoom {
                removeIds.compactMap { id in
                    guard let entity = existingByIdAfterCleanup[id] else { return nil }
                    let isCluster = id.hasPrefix("cluster_")
                    let target: GeoPoint
                    if isCluster {
                        let cluster = entity.state.extra as? MarkerCluster
                        let memberIds = cluster?.markerIds ?? []
                        if memberIds.isEmpty { return nil }
                        let memberTargets = memberIds.compactMap { nextClusterMemberCenters[$0] }
                        if memberTargets.isEmpty { return nil }
                        target = averageGeoPoints(points: memberTargets)
                    } else {
                        guard let nextTarget = nextClusterMemberCenters[id] else { return nil }
                        target = nextTarget
                    }
                    return AnimatedRemove(entity: entity, target: target)
                }
            } else {
                []
            }
        let animatedRemoveIds = Set(animatedRemoveEntries.map { $0.entity.state.id })

        let animatedAddEntries: [AnimatedAdd] =
            if animateZoom {
                addStates.compactMap { state in
                    let isCluster = state.id.hasPrefix("cluster_")
                    let start: GeoPoint
                    if isCluster {
                        let cluster = state.extra as? MarkerCluster
                        let memberIds = cluster?.markerIds ?? []
                        if memberIds.isEmpty { return nil }
                        let memberStarts = memberIds.compactMap { previousClusterMemberCenters[$0] }
                        if memberStarts.isEmpty { return nil }
                        start = averageGeoPoints(points: memberStarts)
                    } else {
                        guard let previous = previousClusterMemberCenters[state.id] else { return nil }
                        start = previous
                    }
                    return AnimatedAdd(state: state, start: start)
                }
            } else {
                []
            }
        let animatedAddIds = Set(animatedAddEntries.map { $0.state.id })

        let immediateRemoveIds = removeIds.subtracting(animatedRemoveIds)
        let immediateAddStates = addStates.filter { !animatedAddIds.contains($0.id) }

        var didImmediateChange = false
        if !immediateRemoveIds.isEmpty {
            let removedEntities = immediateRemoveIds.compactMap { renderedMarkerEntities[$0] }
            if !removedEntities.isEmpty {
                await renderer.onRemove(data: removedEntities)
                for entity in removedEntities {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                didImmediateChange = true
            }
        }

        if !immediateAddStates.isEmpty {
            let addParams = immediateAddStates.map { state in
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
                renderedMarkerEntities[entity.state.id] = entity
            }
            didImmediateChange = true
        }

        var changeParams: [MarkerOverlayChangeParams<ActualMarker>] = []
        var changeEntities: [MarkerEntity<ActualMarker>] = []

        for state in updateStates {
            guard let prev = existingByIdAfterCleanup[state.id] else { continue }
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
                renderedMarkerEntities[entity.state.id] = entity
            }
            didImmediateChange = true
        }

        if didImmediateChange {
            await renderer.onPostProcess()
        }

        if !animateZoom || (animatedRemoveEntries.isEmpty && animatedAddEntries.isEmpty) {
            return
        }
        if token != currentToken() { return }

        let animatedStartEntities: [MarkerEntity<ActualMarker>]
        if !animatedAddEntries.isEmpty {
            let animatedStartStates = animatedAddEntries.map { entry in
                entry.state.copy(position: entry.start)
            }
            animatedStartEntities = await addStatesToRenderer(states: animatedStartStates, renderer: renderer)
            await renderer.onPostProcess()
        } else {
            animatedStartEntities = []
        }

        var moves: [AnimatedMove<ActualMarker>] = []
        for entry in animatedAddEntries {
            guard let entity = markerManager.getEntity(entry.state.id) else { continue }
            moves.append(
                AnimatedMove(
                    id: entry.state.id,
                    start: entry.start,
                    end: GeoPoint.from(position: entry.state.position),
                    baseState: entry.state,
                    entity: entity
                )
            )
        }
        for entry in animatedRemoveEntries {
            moves.append(
                AnimatedMove(
                    id: entry.entity.state.id,
                    start: GeoPoint.from(position: entry.entity.state.position),
                    end: entry.target,
                    baseState: entry.entity.state,
                    entity: entry.entity
                )
            )
        }

        let completed = await animateMarkerMoves(
            moves: moves,
            renderer: renderer,
            durationMillis: zoomAnimationDurationMillis,
            token: token
        )

        if !animatedRemoveEntries.isEmpty {
            let entitiesToRemove = animatedRemoveEntries
                .map { $0.entity }
                .filter { renderedMarkerEntities[$0.state.id] != nil }
            if !entitiesToRemove.isEmpty {
                await renderer.onRemove(data: entitiesToRemove)
                for entity in entitiesToRemove {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                await renderer.onPostProcess()
            }
        }

        if !completed, !animatedStartEntities.isEmpty {
            let entitiesToRemoveOnCancel = animatedStartEntities
                .filter { renderedMarkerEntities[$0.state.id] != nil }
            if !entitiesToRemoveOnCancel.isEmpty {
                await renderer.onRemove(data: entitiesToRemoveOnCancel)
                for entity in entitiesToRemoveOnCancel {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                await renderer.onPostProcess()
            }
        }
    }

    private func addStatesToRenderer<Renderer: MarkerOverlayRendererProtocol>(
        states: [MarkerState],
        renderer: Renderer
    ) async -> [MarkerEntity<ActualMarker>] where Renderer.ActualMarker == ActualMarker {
        guard !states.isEmpty else { return [] }
        let addParams = states.map { state in
            MarkerOverlayAddParams(
                state: state,
                bitmapIcon: state.icon?.toBitmapIcon() ?? defaultMarkerIcon
            )
        }
        let actualMarkers = await renderer.onAdd(data: addParams)
        var addedEntities: [MarkerEntity<ActualMarker>] = []
        for (index, actualMarker) in actualMarkers.enumerated() {
            guard let actualMarker else { continue }
            let entity = MarkerEntity(
                marker: actualMarker,
                state: addParams[index].state,
                visible: true,
                isRendered: true
            )
            markerManager.registerEntity(entity)
            renderedMarkerEntities[entity.state.id] = entity
            addedEntities.append(entity)
        }
        return addedEntities
    }

    private func animateMarkerMoves<Renderer: MarkerOverlayRendererProtocol>(
        moves: [AnimatedMove<ActualMarker>],
        renderer: Renderer,
        durationMillis: Int,
        token: Int64
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        if moves.isEmpty { return true }
        var activeMoves = moves
        let steps = max(1, durationMillis / Self.animationFrameMillis)
        let stepMillis = steps <= 1 ? durationMillis : Self.animationFrameMillis
        for step in 1...steps {
            if token != currentToken() { return false }
            if Task.isCancelled { return false }
            let t = Double(step) / Double(steps)
            var changeParams: [MarkerOverlayChangeParams<ActualMarker>] = []
            var changeEntities: [MarkerEntity<ActualMarker>] = []
            for move in activeMoves {
                let position = interpolatePosition(start: move.start, end: move.end, t: t)
                let nextState = move.baseState.copy(position: position)
                let prevEntity = move.entity
                let nextEntity = MarkerEntity(
                    marker: prevEntity.marker,
                    state: nextState,
                    visible: true,
                    isRendered: true
                )
                let change = MarkerOverlayChangeParams(
                    current: nextEntity,
                    bitmapIcon: nextState.icon?.toBitmapIcon() ?? defaultMarkerIcon,
                    prev: prevEntity
                )
                changeParams.append(change)
                changeEntities.append(nextEntity)
            }
            if !changeParams.isEmpty {
                let actualMarkers = await renderer.onChange(data: changeParams)
                for (index, actualMarker) in actualMarkers.enumerated() {
                    let fallbackMarker = activeMoves[index].entity.marker
                    let updatedMarker = actualMarker ?? fallbackMarker
                    let updatedEntity = MarkerEntity(
                        marker: updatedMarker,
                        state: changeEntities[index].state,
                        visible: true,
                        isRendered: true
                    )
                    markerManager.updateEntity(updatedEntity)
                    renderedMarkerEntities[updatedEntity.state.id] = updatedEntity
                    activeMoves[index].entity = updatedEntity
                }
                await renderer.onPostProcess()
            }
            if step < steps {
                let nanos = UInt64(stepMillis) * 1_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
        return true
    }

    private func interpolatePosition(start: GeoPointProtocol, end: GeoPointProtocol, t: Double) -> GeoPoint {
        let startAlt = start.altitude ?? 0.0
        let endAlt = end.altitude ?? 0.0
        return GeoPoint(
            latitude: start.latitude + (end.latitude - start.latitude) * t,
            longitude: start.longitude + (end.longitude - start.longitude) * t,
            altitude: startAlt + (endAlt - startAlt) * t
        )
    }

    private func averageGeoPoints(points: [GeoPoint]) -> GeoPoint {
        if points.isEmpty { return GeoPoint(latitude: 0.0, longitude: 0.0) }
        var sumLat = 0.0
        var sumLon = 0.0
        for point in points {
            sumLat += point.latitude
            sumLon += point.longitude
        }
        let count = Double(points.count)
        return GeoPoint(latitude: sumLat / count, longitude: sumLon / count)
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

    private func updateClusteringTurn(zoom: Double) -> ZoomChange {
        let zoomKey = Int((zoom * 100.0).rounded())
        if lastZoomKey == nil {
            clusteringTurn = 1
            lastZoomKey = zoomKey
            return ZoomChange(turn: clusteringTurn, zoomChanged: false)
        }
        let zoomChanged = lastZoomKey != zoomKey
        if zoomChanged {
            clusteringTurn += 1
            lastZoomKey = zoomKey
        }
        return ZoomChange(turn: clusteringTurn, zoomChanged: zoomChanged)
    }

    private func hasCameraMoved(previous: MapCameraPosition, current: MapCameraPosition) -> Bool {
        let distance = Spherical.computeDistanceBetween(previous.position, current.position)
        if distance > Self.panAnimationMinDistanceMeters { return true }
        if abs(previous.bearing - current.bearing) > Self.cameraAngleEpsilon { return true }
        return abs(previous.tilt - current.tilt) > Self.cameraAngleEpsilon
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

    public static var defaultIconProvider: ClusterIconProvider {
        { count in DefaultMarkerIcon(label: String(count)) }
    }

    private struct ClusterCandidate {
        let center: GeoPoint
        let members: [MarkerState]
    }

    private struct MergedCluster {
        let center: GeoPoint
        let members: [MarkerState]
    }

    private struct AnimatedAdd {
        let state: MarkerState
        let start: GeoPoint
    }

    private struct AnimatedRemove<ActualMarker> {
        let entity: MarkerEntity<ActualMarker>
        let target: GeoPoint
    }

    private struct AnimatedMove<ActualMarker> {
        let id: String
        let start: GeoPointProtocol
        let end: GeoPointProtocol
        let baseState: MarkerState
        var entity: MarkerEntity<ActualMarker>
    }

    private struct RenderRequest {
        let cameraPosition: MapCameraPosition
        let viewport: GeoRectBounds
        let renderer: AnyMarkerOverlayRenderer<ActualMarker>
        let token: Int64
    }

    private struct ZoomChange {
        let turn: Int
        let zoomChanged: Bool
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
