import Combine
import Foundation
import MapConductorCore

private let markerClusterDefaultClusterRadiusPx: Double = 60.0
private let markerClusterDefaultMinClusterSize: Int = 2
private let markerClusterDefaultExpandMargin: Double = 0.2
private let markerClusterDefaultTileSize: Double = 256.0
private let markerClusterDefaultZoomAnimationDurationMillis: Int = 200
public let markerClusterCameraDebounceMillis: Int = 100
private let markerClusterAnimationFrameMillis: Int = 16
private let markerClusterMaxDenseCells: Int = 4
private let markerClusterMaxDenseCandidates: Int = 50
private let markerClusterPanAnimationMinDistanceMeters: Double = 1.0
private let markerClusterCameraAngleEpsilon: Double = 1e-2
private let markerClusterMinZoomDeltaForRender: Double = 0.02
private let markerClusterDegToRad: Double = Double.pi / 180.0
private let markerClusterMaxSinLat: Double = 0.9999

private enum MarkerClusterStrategyInstanceId {
    private static let lock = NSLock()
    private static var next: Int = 0

    static func allocate() -> Int {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return next
    }
}

public final class MarkerClusterStrategy<ActualMarker>: AbstractMarkerRenderingStrategy<ActualMarker> {
    public static var DEFAULT_CLUSTER_RADIUS_PX: Double { markerClusterDefaultClusterRadiusPx }
    public static var DEFAULT_MIN_CLUSTER_SIZE: Int { markerClusterDefaultMinClusterSize }
    public static var DEFAULT_EXPAND_MARGIN: Double { markerClusterDefaultExpandMargin }
    public static var DEFAULT_TILE_SIZE: Double { markerClusterDefaultTileSize }
    public static var DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS: Int { markerClusterDefaultZoomAnimationDurationMillis }
    public static var DEFAULT_CAMERA_DEBOUNCE_MILLIS: Int { markerClusterCameraDebounceMillis }

    private static var cameraDebounceMillis: Int { markerClusterCameraDebounceMillis }
    private static var animationFrameMillis: Int { markerClusterAnimationFrameMillis }
    private static var maxDenseCells: Int { markerClusterMaxDenseCells }
    private static var maxDenseCandidates: Int { markerClusterMaxDenseCandidates }
    private static var panAnimationMinDistanceMeters: Double { markerClusterPanAnimationMinDistanceMeters }
    private static var cameraAngleEpsilon: Double { markerClusterCameraAngleEpsilon }
    private static var minZoomDeltaForRender: Double { markerClusterMinZoomDeltaForRender }
    private static var degToRad: Double { markerClusterDegToRad }
    private static var maxSinLat: Double { markerClusterMaxSinLat }

    public typealias ClusterIconProvider = (Int) -> MarkerIconProtocol
    public typealias ClusterIconProviderWithTurn = (Int, Int) -> MarkerIconProtocol

	    private let instanceId: Int = MarkerClusterStrategyInstanceId.allocate()

    public let clusterRadiusPx: Double
    public let minClusterSize: Int
    public let expandMargin: Double
    public let clusterIconProvider: ClusterIconProvider
    public let clusterIconProviderWithTurn: ClusterIconProviderWithTurn?
    public let tileSize: Double
    public let onClusterClick: ((MarkerCluster) -> Void)?
    public let enableZoomAnimation: Bool
    public let enablePanAnimation: Bool
    public let zoomAnimationDurationMillis: Int
    public let cameraIdleDebounceMillis: Int

    private var sourceStates: [String: MarkerState] = [:]
    private var sourceFingerprints: [String: MarkerFingerPrint] = [:]
    private var lastCameraPosition: MapCameraPosition?
    private var clusteringTurn: Int = 0
    private var lastZoomKey: Int?
    private var debounceTask: Task<Void, Never>?
    private var cameraUpdateToken: Int64 = 0
    private let tokenLock = NSLock()
    private let renderQueueState = RenderQueueState()
    private var renderTask: Task<Void, Never>?
    private var lastViewport: GeoRectBounds?
    private let rendererBox = MainQueueReleaseBox<AnyMarkerOverlayRenderer<ActualMarker>>()

    private let debugInfoSubject = CurrentValueSubject<[MarkerClusterDebugInfo], Never>([])
    public var debugInfoFlow: CurrentValueSubject<[MarkerClusterDebugInfo], Never> { debugInfoSubject }
    private var lastClusterMemberCenters: [String: GeoPoint] = [:]
    private var lastClusterPositions: [String: GeoPoint] = [:]
    private var lastRenderCameraPosition: MapCameraPosition?
    private var renderedMarkerEntities: [String: MarkerEntity<ActualMarker>] = [:]
    private var lastExpandedBounds: GeoRectBounds?
    private var lastClusterCoverageBounds: GeoRectBounds?
    private var lastClusterAssignments: [String: String] = [:]  // markerID -> clusterID
    private var lastSourceStateVersion: Int64 = 0
    private var lastSourceFingerprints: [String: MarkerFingerPrint] = [:]
    private let sourceStatesLock = NSLock()
    private let renderStateLock = NSLock()
    private var sourceStateVersion: Int64 = 0

    public init(
        clusterRadiusPx: Double = DEFAULT_CLUSTER_RADIUS_PX,
        minClusterSize: Int = DEFAULT_MIN_CLUSTER_SIZE,
        expandMargin: Double = DEFAULT_EXPAND_MARGIN,
        clusterIconProvider: @escaping ClusterIconProvider = MarkerClusterStrategy.defaultIconProvider,
        clusterIconProviderWithTurn: ClusterIconProviderWithTurn? = nil,
        onClusterClick: ((MarkerCluster) -> Void)? = nil,
        enableZoomAnimation: Bool = false,
        enablePanAnimation: Bool = false,
        zoomAnimationDurationMillis: Int = DEFAULT_ZOOM_ANIMATION_DURATION_MILLIS,
        cameraIdleDebounceMillis: Int = DEFAULT_CAMERA_DEBOUNCE_MILLIS,
        tileSize: Double = DEFAULT_TILE_SIZE,
        semaphore: AsyncSemaphore = AsyncSemaphore(1)
    ) {
        self.clusterRadiusPx = clusterRadiusPx
        self.minClusterSize = minClusterSize
        self.expandMargin = expandMargin
        self.clusterIconProvider = clusterIconProvider
        self.clusterIconProviderWithTurn = clusterIconProviderWithTurn
        self.onClusterClick = onClusterClick
        self.enableZoomAnimation = enableZoomAnimation
        self.enablePanAnimation = enablePanAnimation
        self.zoomAnimationDurationMillis = zoomAnimationDurationMillis
        self.cameraIdleDebounceMillis = cameraIdleDebounceMillis
        self.tileSize = tileSize
        super.init(semaphore: semaphore)
    }

    deinit {
        MCLog.marker("MarkerClusterStrategy[\(instanceId)].deinit")
        // Increment token first to stop any ongoing operations
        _ = incrementToken()

        // Cancel debounce task
        debounceTask?.cancel()
        debounceTask = nil

        // Clear queue and cancel render task
        // Note: We can't await in deinit, but clearing the queue will cause
        // processRenderQueue to exit naturally on its next iteration
        let queueState = renderQueueState
        Task {
            await queueState.clear()
        }

        // Cancel render task - it should exit due to token check
        renderTask?.cancel()
        renderTask = nil
    }

    public override func clear() {
        MCLog.marker("MarkerClusterStrategy[\(instanceId)].clear")
        // Increment token first to stop any ongoing operations
        _ = incrementToken()

        // Cancel debounce task
        debounceTask?.cancel()
        debounceTask = nil

        // Clear queue and cancel render task
        let queueState = renderQueueState
        Task {
            await queueState.clear()
        }
        renderTask?.cancel()
        renderTask = nil

        Task { @MainActor [weak self] in
            self?.rendererBox.set(nil)
        }

        // Clear state
        sourceStates.removeAll()
        sourceFingerprints.removeAll()
        markerManager.clear()
        debugInfoSubject.value = []

        renderStateLock.lock()
        lastClusterMemberCenters = [:]
        lastClusterPositions = [:]
        lastRenderCameraPosition = nil
        renderedMarkerEntities.removeAll()
        lastZoomKey = nil
        clusteringTurn = 0
        lastExpandedBounds = nil
        lastClusterCoverageBounds = nil
        lastClusterAssignments = [:]
        lastSourceStateVersion = 0
        lastSourceFingerprints = [:]
        renderStateLock.unlock()

        sourceStatesLock.lock()
        sourceStateVersion = 0
        sourceStatesLock.unlock()
    }

	    public override func onAdd<Renderer: MarkerOverlayRendererProtocol>(
	        data: [MarkerState],
	        viewport: GeoRectBounds,
	        renderer: Renderer
	    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        guard let cameraPosition = lastCameraPosition else { return true }
        MCLog.marker("MarkerClusterStrategy[\(instanceId)].onAdd count=\(data.count)")
        lastViewport = viewport
	        updateSourceStates(data)
	        await MainActor.run { [weak self] in
	            guard let self else { return }
	            self.rendererBox.set(AnyMarkerOverlayRenderer(renderer))
	            self.enqueueRender(cameraPosition: cameraPosition, viewport: viewport, token: self.currentToken())
	        }
	        return true
	    }

	    public override func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
	        state: MarkerState,
	        viewport: GeoRectBounds,
	        renderer: Renderer
	    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        guard let cameraPosition = lastCameraPosition else { return true }
        MCLog.marker("MarkerClusterStrategy[\(instanceId)].onUpdate id=\(state.id)")
        sourceStatesLock.lock()
        let nextFingerprint = state.fingerPrint()
        let prevFingerprint = sourceFingerprints[state.id]
        sourceStates[state.id] = state
        sourceFingerprints[state.id] = nextFingerprint
        if prevFingerprint != nextFingerprint {
            sourceStateVersion &+= 1
        }
        sourceStatesLock.unlock()
	        lastViewport = viewport
	        await MainActor.run { [weak self] in
	            guard let self else { return }
	            self.rendererBox.set(AnyMarkerOverlayRenderer(renderer))
	            self.enqueueRender(cameraPosition: cameraPosition, viewport: viewport, token: self.currentToken())
	        }
	        return true
	    }

	    public override func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
	        mapCameraPosition: MapCameraPosition,
	        renderer: Renderer
	    ) async where Renderer.ActualMarker == ActualMarker {
        lastCameraPosition = mapCameraPosition
	        MCLog.marker("MarkerClusterStrategy[\(instanceId)].onCameraChanged zoom=\(mapCameraPosition.zoom)")
	        await MainActor.run { [weak self] in
	            guard let self else { return }
	            self.rendererBox.set(AnyMarkerOverlayRenderer(renderer))
	        }
	        let token = incrementToken()
	        debounceTask?.cancel()
	        debounceTask = Task { [weak self] in
            guard let self else { return }
            let nanos = UInt64(cameraIdleDebounceMillis) * 1_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard token == self.currentToken() else { return }
            let viewport =
                mapCameraPosition.visibleRegion?.bounds ??
                self.lastViewport
            guard let viewport else {
                MCLog.marker("MarkerClusterStrategy[\(self.instanceId)].onCameraChanged viewportMissing")
                return
            }
            self.lastViewport = viewport
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.enqueueRender(cameraPosition: mapCameraPosition, viewport: viewport, token: token)
            }
        }
    }

	    @MainActor
	    private func enqueueRender(
	        cameraPosition: MapCameraPosition,
	        viewport: GeoRectBounds,
	        token: Int64
	    ) {
	        guard rendererBox.get() != nil else {
	            MCLog.marker("MarkerClusterStrategy[\(instanceId)].enqueueRender skipped: rendererMissing token=\(token)")
	            return
	        }
	        let request = RenderRequest(cameraPosition: cameraPosition, viewport: viewport, token: token)
	        Task { [renderQueueState] in await renderQueueState.enqueue(request) }
	        MCLog.marker("MarkerClusterStrategy[\(instanceId)].enqueueRender token=\(token)")
	        if renderTask == nil {
	            renderTask = Task { [weak self] in
	                guard let self else { return }
                await self.processRenderQueue()
            }
        }
    }

    private func processRenderQueue() async {
        while true {
            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.renderTask = nil
                }
                return
            }
            let request = await renderQueueState.take()
            guard let request else {
                await MainActor.run { [weak self] in
                    self?.renderTask = nil
                }
                return
            }

            MCLog.marker("MarkerClusterStrategy[\(instanceId)].processRenderQueue token=\(request.token)")
            await self.renderClusters(cameraPosition: request.cameraPosition, viewport: request.viewport, token: request.token)
        }
    }

    private func updateSourceStates(_ data: [MarkerState]) {
        sourceStatesLock.lock()
        defer { sourceStatesLock.unlock() }
        let nextIds = Set(data.map { $0.id })
        let removedIds = Set(sourceStates.keys).subtracting(nextIds)
        var changed = false
        removedIds.forEach {
            sourceStates.removeValue(forKey: $0)
            sourceFingerprints.removeValue(forKey: $0)
            changed = true
        }
        data.forEach { state in
            let nextFingerprint = state.fingerPrint()
            let prevFingerprint = sourceFingerprints[state.id]
            if prevFingerprint != nextFingerprint {
                changed = true
            }
            sourceStates[state.id] = state
            sourceFingerprints[state.id] = nextFingerprint
        }
        if changed {
            sourceStateVersion &+= 1
        }
    }

    private func renderClusters(
        cameraPosition: MapCameraPosition,
        viewport: GeoRectBounds,
        token: Int64
    ) async {
        // Check before entering semaphore to avoid blocking
        if Task.isCancelled { return }
        if token != currentToken() { return }

	        await semaphore.withPermit {
	            // Double-check cancellation and renderer validity after acquiring semaphore
	            if Task.isCancelled { return }
	            if token != currentToken() { return }
	            guard rendererBox.get() != nil else {
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].renderClusters aborted: rendererMissing")
	                return
	            }
	            let expandedBounds = expandBounds(bounds: viewport, margin: expandMargin)
	            let zoom = cameraPosition.zoom
	            let zoomChange = updateClusteringTurn(zoom: zoom)
	            let turn = zoomChange.turn
            let zoomChanged = zoomChange.zoomChanged
            renderStateLock.lock()
            let lastRenderCameraPositionSnapshot = lastRenderCameraPosition
            let lastClusterCoverageBoundsSnapshot = lastClusterCoverageBounds
            let lastClusterAssignmentsSnapshot = lastClusterAssignments
            let lastClusterPositionsSnapshot = lastClusterPositions
            let lastClusterMemberCentersSnapshot = lastClusterMemberCenters
            let lastSourceStateVersionSnapshot = lastSourceStateVersion
            let lastSourceFingerprintsSnapshot = lastSourceFingerprints
            renderStateLock.unlock()
            let sourceStateVersionSnapshot: Int64 = {
                sourceStatesLock.lock()
                defer { sourceStatesLock.unlock() }
                return sourceStateVersion
            }()
            let cameraMoved = lastRenderCameraPositionSnapshot.map { hasCameraMoved(previous: $0, current: cameraPosition) } ?? false
            let animateTransitions =
                (enableZoomAnimation && zoomChanged) ||
                (enablePanAnimation && cameraMoved)
	        MCLog.marker("MarkerClusterStrategy[\(instanceId)].renderClusters token=\(token) zoom=\(zoom) animate=\(animateTransitions)")

            if zoomChanged,
               let lastRendered = lastRenderCameraPositionSnapshot,
               abs(zoom - lastRendered.zoom) < MarkerClusterStrategy.minZoomDeltaForRender {
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].renderClusters earlyReturn token=\(token) reason=zoomDeltaTooSmall")
                return
            }

            // Early return optimization: if panning and previous coverage contains current viewport (and markers didn't change), no need to recalculate
            if !zoomChanged,
               let lastClusterCoverageBoundsSnapshot,
               containsBounds(container: lastClusterCoverageBoundsSnapshot, target: expandedBounds),
               sourceStateVersionSnapshot == lastSourceStateVersionSnapshot {
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].renderClusters earlyReturn token=\(token) reason=boundsContained")
                renderStateLock.lock()
                lastRenderCameraPosition = cameraPosition
                renderStateLock.unlock()
                return
            }

            var debugInfos: [MarkerClusterDebugInfo] = []
            var clusterMemberCenters: [String: GeoPoint] = [:]
            var clusterPositions: [String: GeoPoint] = [:]

            // Clear cluster assignments on zoom change to force full reclustering
            if zoomChanged {
                renderStateLock.lock()
                lastClusterAssignments = [:]
                renderStateLock.unlock()
            }

            // Partition markers: cached (already clustered) vs new (need clustering)
            var cachedMarkers: [MarkerState] = []
            var newMarkers: [MarkerState] = []

            let sourceSnapshot: [MarkerState] = {
                sourceStatesLock.lock()
                defer { sourceStatesLock.unlock() }
                return Array(sourceStates.values)
            }()
            for state in sourceSnapshot {
                if Task.isCancelled { return }
                if token != currentToken() { return }
                if !expandedBounds.contains(point: state.position) { continue }

                let currentFingerprint = state.fingerPrint()
                let lastFingerprint = lastSourceFingerprintsSnapshot[state.id]
                let movedSinceLastRender =
                    lastFingerprint != nil &&
                    (lastFingerprint?.latitude != currentFingerprint.latitude ||
                     lastFingerprint?.longitude != currentFingerprint.longitude)

                if let lastCoverageBounds = lastClusterCoverageBoundsSnapshot,
                   !zoomChanged,
                   lastCoverageBounds.contains(point: state.position),
                   lastClusterAssignmentsSnapshot[state.id] != nil,
                   !movedSinceLastRender {
                    cachedMarkers.append(state)
                } else {
                    newMarkers.append(state)
                }
            }

	            MCLog.marker("MarkerClusterStrategy[\(instanceId)].partition token=\(token) cached=\(cachedMarkers.count) new=\(newMarkers.count)")

            // Rebuild cached cluster groups from assignments
            var cachedClusterGroups: [String: [MarkerState]] = [:]
            var cachedMarkerGroups: [String: [MarkerState]] = [:]
            for marker in cachedMarkers {
                if let clusterId = lastClusterAssignmentsSnapshot[marker.id] {
                    if clusterId.hasPrefix("cluster_") {
                        cachedClusterGroups[clusterId, default: []].append(marker)
                    } else {
                        cachedMarkerGroups[clusterId, default: []].append(marker)
                    }
                } else {
                    cachedMarkerGroups[marker.id, default: []].append(marker)
                }
            }

            // Early return check before heavy processing
            if Task.isCancelled { return }
            if token != currentToken() { return }

            // Apply standard clustering only to new markers
            var newClustered: [ClusterCell: [MarkerState]] = [:]
            for state in newMarkers {
                if Task.isCancelled { return }
                if token != currentToken() { return }
                let (x, y) = projectToPixel(position: state.position, zoom: zoom, tileSize: tileSize)
                let cell = ClusterCell(
                    x: Int(floor(x / clusterRadiusPx)),
                    y: Int(floor(y / clusterRadiusPx))
                )
                newClustered[cell, default: []].append(state)
            }

            let newCandidates = newClustered.keys.sorted { lhs, rhs in
                if lhs.x == rhs.x { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }.compactMap { cell -> ClusterCandidate? in
                guard let members = newClustered[cell], let center = members.first?.position else { return nil }
                return ClusterCandidate(
                    center: GeoPoint.from(position: center),
                    members: members
                )
            }

            // Early return check before heavy processing
            if Task.isCancelled { return }
            if token != currentToken() { return }

            let newMergedClusters = mergeClusters(candidates: newCandidates, zoom: zoom)

            // Early return check after heavy processing
            if Task.isCancelled { return }
            if token != currentToken() { return }

            // Merge new clusters with nearby cached clusters
            var finalMergedClusters: [MergedCluster] = []
            var usedCachedClusters: Set<String> = []

            for newCluster in newMergedClusters {
                if Task.isCancelled { return }
                if token != currentToken() { return }

                var mergedWithCached = false
                let newCenter = newCluster.center

                // Check proximity to cached cluster positions
                for (cachedClusterId, cachedMembers) in cachedClusterGroups {
                    guard !usedCachedClusters.contains(cachedClusterId) else { continue }
                    guard let cachedPosition = lastClusterPositionsSnapshot[cachedClusterId] else { continue }

                    let metersPerPixelVal = metersPerPixel(position: newCenter, zoom: zoom, tileSize: tileSize)
                    let thresholdMeters = clusterRadiusPx * metersPerPixelVal
                    let distance = Spherical.computeDistanceBetween(newCenter, cachedPosition)

                    if distance <= thresholdMeters {
                        // Merge new markers into cached cluster
                        let combinedMembers = cachedMembers + newCluster.members
                        finalMergedClusters.append(
                            MergedCluster(center: cachedPosition, members: combinedMembers)
                        )
                        usedCachedClusters.insert(cachedClusterId)
                        mergedWithCached = true
                        break
                    }
                }

                if !mergedWithCached {
                    // New cluster stands alone
                    finalMergedClusters.append(newCluster)
                }
            }

            // Add unmerged cached clusters
            for (cachedClusterId, cachedMembers) in cachedClusterGroups {
                guard !usedCachedClusters.contains(cachedClusterId) else { continue }
                if let cachedPosition = lastClusterPositionsSnapshot[cachedClusterId] {
                    finalMergedClusters.append(
                        MergedCluster(center: cachedPosition, members: cachedMembers)
                    )
                }
            }

            // Track which marker IDs have already been used in clusters to prevent duplicates
            var usedMarkerIds = Set<String>()
            for merged in finalMergedClusters {
                for member in merged.members {
                    usedMarkerIds.insert(member.id)
                }
            }

            // Keep cached single markers ONLY if not already used in a cluster
            for (_, cachedMembers) in cachedMarkerGroups {
                let unusedMembers = cachedMembers.filter { !usedMarkerIds.contains($0.id) }
                guard !unusedMembers.isEmpty else { continue }
                guard let center = unusedMembers.first?.position else { continue }
                finalMergedClusters.append(
                    MergedCluster(center: GeoPoint.from(position: center), members: unusedMembers)
                )
                // Track these newly added markers
                for member in unusedMembers {
                    usedMarkerIds.insert(member.id)
                }
            }

            let mergedClusters = finalMergedClusters
            var desiredStates: [MarkerState] = []
            let coverageBounds = GeoRectBounds()
            var nextClusterAssignments: [String: String] = [:]

            // Debug: verify no duplicate markers in mergedClusters
            #if DEBUG
            var allMemberIds = Set<String>()
            var duplicateMemberIds = Set<String>()
            for merged in mergedClusters {
                for member in merged.members {
                    if allMemberIds.contains(member.id) {
                        duplicateMemberIds.insert(member.id)
                    }
                    allMemberIds.insert(member.id)
                }
            }
            if !duplicateMemberIds.isEmpty {
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].WARNING token=\(token) duplicateMembersInMergedClusters=\(duplicateMemberIds)")
            }
            #endif

            for merged in mergedClusters {
                if Task.isCancelled { return }
                if token != currentToken() { return }
                if merged.members.count >= minClusterSize {
                    // First compute initial center to determine cluster cell/ID
                    let initialCenter = merged.center
                    let (cx, cy) = projectToPixel(position: initialCenter, zoom: zoom, tileSize: tileSize)
                    let cell = ClusterCell(
                        x: Int(floor(cx / clusterRadiusPx)),
                        y: Int(floor(cy / clusterRadiusPx))
                    )
                    let clusterId = buildClusterId(cell: cell, zoom: zoom)

                    // Check if we have a cached position for this cluster.
                    // Reuse it during panning to prevent cluster markers from moving unnecessarily,
                    // but only when marker source states haven't changed since last render.
                    let center: GeoPoint
                    if let cachedPosition = lastClusterPositionsSnapshot[clusterId],
                       !zoomChanged,
                       sourceStateVersionSnapshot == lastSourceStateVersionSnapshot {
                        center = cachedPosition
                    } else {
                        center = initialCenter
                    }
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
                    extendCoverageBounds(bounds: coverageBounds, center: center, radiusMeters: radiusMeters)
                    for member in merged.members {
                        clusterMemberCenters[member.id] = center
                        nextClusterAssignments[member.id] = clusterId
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
                    merged.members.forEach { member in
                        coverageBounds.extend(point: member.position)
                        nextClusterAssignments[member.id] = member.id
                    }
                    desiredStates.append(contentsOf: merged.members)
                }
            }

            if token != currentToken() { return }

            // Debug: verify no duplicate IDs in desiredStates
            #if DEBUG
            let uniqueDesiredIds = Set(desiredStates.map { $0.id })
            if uniqueDesiredIds.count != desiredStates.count {
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].ERROR token=\(token) duplicateIdsInDesiredStates count=\(desiredStates.count) unique=\(uniqueDesiredIds.count)")
                var seenIds = Set<String>()
                var duplicates = Set<String>()
                for state in desiredStates {
                    if seenIds.contains(state.id) {
                        duplicates.insert(state.id)
                    }
                    seenIds.insert(state.id)
                }
	                MCLog.marker("MarkerClusterStrategy[\(instanceId)].duplicateIds token=\(token) ids=\(duplicates)")
            }
            #endif

	            await applyRender(
		                desiredStates: desiredStates,
		                token: token,
		                animateTransitions: animateTransitions,
	                debugInfos: debugInfos,
	                previousClusterMemberCenters: lastClusterMemberCentersSnapshot,
	                nextClusterMemberCenters: clusterMemberCenters,
	                previousClusterPositions: lastClusterPositionsSnapshot,
	                nextClusterPositions: clusterPositions
	            )
	            renderStateLock.lock()
	            lastClusterMemberCenters = clusterMemberCenters
	            lastClusterPositions = clusterPositions
	            lastClusterAssignments = nextClusterAssignments
            lastRenderCameraPosition = cameraPosition
            lastExpandedBounds = expandedBounds
            lastClusterCoverageBounds = coverageBounds.isEmpty ? nil : coverageBounds
            lastSourceStateVersion = sourceStateVersionSnapshot
            // Keep fingerprints for marker move invalidation.
            // (Only update the entries we saw this render to avoid scanning all markers again.)
            for state in sourceSnapshot {
                lastSourceFingerprints[state.id] = state.fingerPrint()
            }
            let renderedCount = renderedMarkerEntities.count
            renderStateLock.unlock()
	            MCLog.marker(
	                "MarkerClusterStrategy[\(instanceId)].renderClusters stats token=\(token) source=\(sourceStates.count) rendered=\(renderedCount) manager=\(markerManager.allEntities().count)"
	            )
	        }
	    }

	    @MainActor
	    private func applyRender(
	        desiredStates: [MarkerState],
	        token: Int64,
	        animateTransitions: Bool,
	        debugInfos: [MarkerClusterDebugInfo],
	        previousClusterMemberCenters: [String: GeoPoint],
	        nextClusterMemberCenters: [String: GeoPoint],
	        previousClusterPositions: [String: GeoPoint],
	        nextClusterPositions: [String: GeoPoint]
	    ) async {
	        guard let renderer = rendererBox.get() else {
	            MCLog.marker("MarkerClusterStrategy[\(instanceId)].applyRender skipped: rendererMissing token=\(token)")
	            return
	        }
	        debugInfoSubject.value = debugInfos
	        await updateRenderedMarkers(
	            desiredStates: desiredStates,
	            renderer: renderer,
	            token: token,
	            animateTransitions: animateTransitions,
	            previousClusterMemberCenters: previousClusterMemberCenters,
	            nextClusterMemberCenters: nextClusterMemberCenters,
	            previousClusterPositions: previousClusterPositions,
	            nextClusterPositions: nextClusterPositions
	        )
	    }

	    @MainActor
	    private func updateRenderedMarkers(
	        desiredStates: [MarkerState],
	        renderer: AnyMarkerOverlayRenderer<ActualMarker>,
	        token: Int64,
	        animateTransitions: Bool,
	        previousClusterMemberCenters: [String: GeoPoint],
	        nextClusterMemberCenters: [String: GeoPoint],
	        previousClusterPositions: [String: GeoPoint],
	        nextClusterPositions: [String: GeoPoint]
	    ) async {
	        // Early return check at start
	        if Task.isCancelled { return }
	        if token != currentToken() { return }

        var desiredById: [String: MarkerState] = [:]
        for state in desiredStates {
            desiredById[state.id] = state
        }
        let animateZoom = animateTransitions && zoomAnimationDurationMillis > 0
        let existing = markerManager.allEntities()
        var existingById: [String: MarkerEntity<ActualMarker>] = [:]
        for entity in existing {
            existingById[entity.state.id] = entity
        }
	        MCLog.marker("MarkerClusterStrategy[\(instanceId)].updateRenderedMarkers token=\(token) desired=\(desiredStates.count) existing=\(existing.count) animate=\(animateZoom)")

        if !animateZoom {
            let orphanedIds = Set(existingById.keys).subtracting(desiredById.keys)
            renderStateLock.lock()
            let orphanedEntitiesBeforeAnimation = orphanedIds.compactMap { renderedMarkerEntities[$0] }
            renderStateLock.unlock()
            if !orphanedEntitiesBeforeAnimation.isEmpty {
                // Check cancellation before renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                await renderer.onRemove(data: orphanedEntitiesBeforeAnimation)

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                renderStateLock.lock()
                for entity in orphanedEntitiesBeforeAnimation {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                renderStateLock.unlock()

                // Check cancellation before renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                await renderer.onPostProcess()

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }
            }
        }

        let existingAfterCleanup = markerManager.allEntities()
        var existingByIdAfterCleanup: [String: MarkerEntity<ActualMarker>] = [:]
        for entity in existingAfterCleanup {
            existingByIdAfterCleanup[entity.state.id] = entity
        }

        let removeIds = Set(existingByIdAfterCleanup.keys).subtracting(desiredById.keys)
        let addStates = desiredById.filter { existingByIdAfterCleanup[$0.key] == nil }.map { $0.value }
        let updateStates = desiredById.filter { existingByIdAfterCleanup[$0.key] != nil }.map { $0.value }

        let animatedRemoveEntries: [AnimatedRemove] =
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
            // Check cancellation before renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            renderStateLock.lock()
            let removedEntities = immediateRemoveIds.compactMap { renderedMarkerEntities[$0] }
            renderStateLock.unlock()
            if !removedEntities.isEmpty {
                await renderer.onRemove(data: removedEntities)

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                renderStateLock.lock()
                for entity in removedEntities {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                renderStateLock.unlock()
                didImmediateChange = true
            }
        }

        if !immediateAddStates.isEmpty {
            // Check cancellation before renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            let addParams = immediateAddStates.map { state in
                MarkerOverlayAddParams(
                    state: state,
                    bitmapIcon: state.icon?.toBitmapIcon() ?? defaultMarkerIcon
                )
            }
            let actualMarkers = await renderer.onAdd(data: addParams)

            // Check cancellation immediately after renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            for (index, actualMarker) in actualMarkers.enumerated() {
                guard let actualMarker else { continue }
                let entity = MarkerEntity(
                    marker: actualMarker,
                    state: addParams[index].state,
                    visible: true,
                    isRendered: true
                )
                markerManager.registerEntity(entity)
                renderStateLock.lock()
                renderedMarkerEntities[entity.state.id] = entity
                renderStateLock.unlock()
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
            // Check cancellation before renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            let actualMarkers = await renderer.onChange(data: changeParams)

            // Check cancellation immediately after renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            for (index, actualMarker) in actualMarkers.enumerated() {
                guard let actualMarker else { continue }
                let entity = MarkerEntity(
                    marker: actualMarker,
                    state: changeEntities[index].state,
                    visible: true,
                    isRendered: true
                )
                markerManager.registerEntity(entity)
                renderStateLock.lock()
                renderedMarkerEntities[entity.state.id] = entity
                renderStateLock.unlock()
            }
            didImmediateChange = true
        }

        if didImmediateChange {
            // Check cancellation before renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            await renderer.onPostProcess()

            // Check cancellation immediately after renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }
        }

        if !animateZoom || (animatedRemoveEntries.isEmpty && animatedAddEntries.isEmpty) {
            return
        }

        // Early return check before animation
        if Task.isCancelled { return }
        if token != currentToken() { return }

        let animatedStartEntities: [MarkerEntity<ActualMarker>]
        if !animatedAddEntries.isEmpty {
            let animatedStartStates = animatedAddEntries.map { entry in
                entry.state.copy(position: entry.start)
            }
            animatedStartEntities = await addStatesToRenderer(states: animatedStartStates, renderer: renderer)

            // Check cancellation before renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }

            await renderer.onPostProcess()

            // Check cancellation immediately after renderer call
            if Task.isCancelled { return }
            if token != currentToken() { return }
        } else {
            animatedStartEntities = []
        }

        var moves: [AnimatedMove] = []
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

        // Early return check after animation
        if Task.isCancelled { return }
        if token != currentToken() { return }

        if !animatedRemoveEntries.isEmpty {
            // Check cancellation before cleanup
            if Task.isCancelled { return }
            if token != currentToken() { return }

            let entitiesToRemove = animatedRemoveEntries
                .map { $0.entity }
                .filter { entity in
                    renderStateLock.lock()
                    let exists = renderedMarkerEntities[entity.state.id] != nil
                    renderStateLock.unlock()
                    return exists
                }
            if !entitiesToRemove.isEmpty {
                await renderer.onRemove(data: entitiesToRemove)

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                renderStateLock.lock()
                for entity in entitiesToRemove {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                renderStateLock.unlock()

                await renderer.onPostProcess()

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }
            }
        }

        if !completed, !animatedStartEntities.isEmpty {
            let entitiesToRemoveOnCancel = animatedStartEntities
                .filter { entity in
                    renderStateLock.lock()
                    let exists = renderedMarkerEntities[entity.state.id] != nil
                    renderStateLock.unlock()
                    return exists
                }
            if !entitiesToRemoveOnCancel.isEmpty {
                await renderer.onRemove(data: entitiesToRemoveOnCancel)

                // Check cancellation immediately after renderer call
                if Task.isCancelled { return }
                if token != currentToken() { return }

                renderStateLock.lock()
                for entity in entitiesToRemoveOnCancel {
                    renderedMarkerEntities.removeValue(forKey: entity.state.id)
                    _ = markerManager.removeEntity(entity.state.id)
                }
                renderStateLock.unlock()

                await renderer.onPostProcess()

                // Check cancellation immediately after renderer call (final)
                if Task.isCancelled { return }
                if token != currentToken() { return }
            }
        }
    }

	    @MainActor
	    private func addStatesToRenderer(
	        states: [MarkerState],
	        renderer: AnyMarkerOverlayRenderer<ActualMarker>
	    ) async -> [MarkerEntity<ActualMarker>] {
	        guard !states.isEmpty else { return [] }

        // Check cancellation before renderer call
        if Task.isCancelled { return [] }

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
            renderStateLock.lock()
            renderedMarkerEntities[entity.state.id] = entity
            renderStateLock.unlock()
            addedEntities.append(entity)
        }
        return addedEntities
    }

	    @MainActor
	    private func animateMarkerMoves(
	        moves: [AnimatedMove],
	        renderer: AnyMarkerOverlayRenderer<ActualMarker>,
	        durationMillis: Int,
	        token: Int64
	    ) async -> Bool {
	        if moves.isEmpty { return true }
	        var activeMoves = moves

        func animationFrameMillis(forMoveCount count: Int) -> Int {
            // Keep small animations smooth, but aggressively drop FPS when many markers move.
            // (Empirically, ~8fps is acceptable for large fan-out / fan-in cluster transitions.)
//            switch count {
//            case ..<50:
//                return 16 // ~60fps
//            case ..<100:
//                return 33 // ~30fps
//            case ..<300:
//                return 74 // ~15fps
//            default:
//                return 125 // ~8fps
//            }
             return 74
        }

        let targetFrameMillis = max(1, min(durationMillis, animationFrameMillis(forMoveCount: activeMoves.count)))
        let steps = max(1, Int(ceil(Double(durationMillis) / Double(targetFrameMillis))))
        let stepMillis = steps <= 1 ? durationMillis : max(1, Int(round(Double(durationMillis) / Double(steps))))

        let moveIcons: [BitmapIcon] = activeMoves.map { $0.baseState.icon?.toBitmapIcon() ?? defaultMarkerIcon }
        for step in 1...steps {
            if token != currentToken() { return false }
            if Task.isCancelled { return false }
            let t = Double(step) / Double(steps)
            var changeParams: [MarkerOverlayChangeParams<ActualMarker>] = []
            changeParams.reserveCapacity(activeMoves.count)
            var changeEntities: [MarkerEntity<ActualMarker>] = []
            changeEntities.reserveCapacity(activeMoves.count)

            for (index, move) in activeMoves.enumerated() {
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
                    bitmapIcon: moveIcons[index],
                    prev: prevEntity
                )
                changeParams.append(change)
                changeEntities.append(nextEntity)
            }
            if !changeParams.isEmpty {
                // Additional check before renderer call in animation loop
                if token != currentToken() { return false }
                if Task.isCancelled { return false }

                let actualMarkers = await renderer.onChange(data: changeParams)

                // Check cancellation immediately after renderer call
                if token != currentToken() { return false }
                if Task.isCancelled { return false }

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
                renderStateLock.lock()
                renderedMarkerEntities[updatedEntity.state.id] = updatedEntity
                renderStateLock.unlock()
                activeMoves[index].entity = updatedEntity
            }

                // Check cancellation before renderer call
                if token != currentToken() { return false }
                if Task.isCancelled { return false }

                await renderer.onPostProcess()

                // Check cancellation immediately after renderer call
                if token != currentToken() { return false }
                if Task.isCancelled { return false }
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

    private func buildClusterId(cell: ClusterCell, zoom: Double) -> String {
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

    private func containsBounds(container: GeoRectBounds, target: GeoRectBounds) -> Bool {
        if container.isEmpty || target.isEmpty { return false }
        guard let sw = target.southWest, let ne = target.northEast else { return false }
        return container.contains(point: sw) && container.contains(point: ne)
    }

    private func extendCoverageBounds(bounds: GeoRectBounds, center: GeoPoint, radiusMeters: Double) {
        let metersPerDegree = 111_320.0
        let latPad = radiusMeters / metersPerDegree
        let lonPad = radiusMeters / (metersPerDegree * max(0.1, cos(center.latitude * Self.degToRad)))
        let expanded = GeoRectBounds(southWest: center, northEast: center)
            .expandedByDegrees(latPad: latPad, lonPad: lonPad)
        _ = bounds.union(other: expanded)
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

    private struct AnimatedRemove {
        let entity: MarkerEntity<ActualMarker>
        let target: GeoPoint
    }

    private struct AnimatedMove {
        let id: String
        let start: GeoPointProtocol
        let end: GeoPointProtocol
        let baseState: MarkerState
        var entity: MarkerEntity<ActualMarker>
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

private actor RenderQueueState {
    private var pending: RenderRequest?

    func enqueue(_ request: RenderRequest) {
        pending = request
    }

    func take() -> RenderRequest? {
        let next = pending
        pending = nil
        return next
    }

    func clear() {
        pending = nil
    }
}

private struct RenderRequest {
    let cameraPosition: MapCameraPosition
    let viewport: GeoRectBounds
    let token: Int64
}

private final class MainQueueReleaseBox<T> {
    private let lock = NSLock()
    private var value: T?

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T?) {
        if !Thread.isMainThread {
            MCLog.marker("MainQueueReleaseBox.set called off main thread")
        }
        let old: T?
        lock.lock()
        old = value
        value = newValue
        lock.unlock()

        guard old != nil else { return }
        DispatchQueue.main.async {
            _ = old
        }
    }

    deinit {
        let old: T?
        lock.lock()
        old = value
        value = nil
        lock.unlock()

        guard old != nil else { return }
        DispatchQueue.main.async {
            _ = old
        }
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
