import Foundation

open class AbstractMarkerController<
    ActualMarker,
    Renderer: MarkerOverlayRendererProtocol
>: OverlayControllerProtocol where Renderer.ActualMarker == ActualMarker {
    public typealias StateType = MarkerState
    public typealias EntityType = MarkerEntity<ActualMarker>
    public typealias EventType = MarkerState

    public let markerManager: MarkerManager<ActualMarker>
    open var renderer: Renderer
    private var rendererRef: Renderer

    public let zIndex: Int = 10
    private let semaphore = AsyncSemaphore(1)
    private let defaultMarkerIcon = DefaultMarkerIcon().toBitmapIcon()

    public var clickListener: ((MarkerState) -> Void)?

    public var dragStartListener: OnMarkerEventHandler?
    public var dragListener: OnMarkerEventHandler?
    public var dragEndListener: OnMarkerEventHandler?
    public var animateStartListener: OnMarkerEventHandler?
    public var animateEndListener: OnMarkerEventHandler?

    private var animatingMarkerIds: Set<String> = []

    public init(
        markerManager: MarkerManager<ActualMarker>,
        renderer: Renderer,
        clickListener: ((MarkerState) -> Void)? = nil
    ) {
        self.markerManager = markerManager
        self.renderer = renderer
        self.rendererRef = renderer
        self.clickListener = clickListener

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rendererRef.animateStartListener = { [weak self] state in
                self?.dispatchAnimateStart(state: state)
            }
            self.rendererRef.animateEndListener = { [weak self] state in
                self?.dispatchAnimateEnd(state: state)
            }
        }
    }

    public func dispatchClick(state: MarkerState) {
        state.onClick?(state)
        clickListener?(state)
    }

    public func dispatchDragStart(state: MarkerState) {
        state.onDragStart?(state)
        dragStartListener?(state)
    }

    public func dispatchDrag(state: MarkerState) {
        state.onDrag?(state)
        dragListener?(state)
    }

    public func dispatchDragEnd(state: MarkerState) {
        state.onDragEnd?(state)
        dragEndListener?(state)
    }

    public func dispatchAnimateStart(state: MarkerState) {
        animatingMarkerIds.insert(state.id)
        state.onAnimateStart?(state)
        animateStartListener?(state)
    }

    public func dispatchAnimateEnd(state: MarkerState) {
        animatingMarkerIds.remove(state.id)
        state.onAnimateEnd?(state)
        animateEndListener?(state)
    }

    open func setDraggingState(markerState: MarkerState, dragging: Bool) {
        // Since this "isDragging" property is internal accessor,
        // childViewControllers must call this method instead of "isDragging = true/false".
    }

    open func add(data: [MarkerState]) async {
        if markerManager.isDestroyed { return }
        MCLog.marker("AbstractMarkerController.add count=\(data.count)")
        await semaphore.withPermit {
            if markerManager.isDestroyed { return }
            var modifiedEntities: [MarkerEntity<ActualMarker>] = []
            var previous = Set(markerManager.allEntities().map { $0.state.id })

            var added: [MarkerOverlayAddParams] = []
            var updated: [MarkerOverlayChangeParams<ActualMarker>] = []
            var removed: [MarkerEntity<ActualMarker>] = []

            for state in data {
                if previous.contains(state.id), let prevEntity = markerManager.getEntity(state.id) {
                    let markerIcon = state.icon?.toBitmapIcon() ?? defaultMarkerIcon
                    updated.append(
                        MarkerOverlayChangeParams(
                            current: MarkerEntity(
                                marker: prevEntity.marker,
                                state: state,
                                isRendered: true
                            ),
                            bitmapIcon: markerIcon,
                            prev: prevEntity
                        )
                    )
                    previous.remove(state.id)
                } else {
                    added.append(
                        MarkerOverlayAddParams(
                            state: state,
                            bitmapIcon: state.icon?.toBitmapIcon() ?? defaultMarkerIcon
                        )
                    )
                    previous.remove(state.id)
                }
            }

            for remainId in previous {
                if let removedEntity = markerManager.removeEntity(remainId) {
                    removed.append(removedEntity)
                }
            }

            if !removed.isEmpty {
                await renderer.onRemove(data: removed)
            }

            if !added.isEmpty {
                let actualMarkers = await renderer.onAdd(data: added)
                for (index, actualMarker) in actualMarkers.enumerated() {
                    guard let actualMarker else { continue }
                    let entity = MarkerEntity(
                        marker: actualMarker,
                        state: added[index].state,
                        isRendered: true
                    )
                    markerManager.registerEntity(entity)
                    modifiedEntities.append(entity)
                }
            }

            if !updated.isEmpty {
                let actualMarkers = await renderer.onChange(data: updated)
                for (index, actualMarker) in actualMarkers.enumerated() {
                    guard let actualMarker else { continue }
                    let params = updated[index]
                    let entity = MarkerEntity(
                        marker: actualMarker,
                        state: params.current.state,
                        isRendered: true
                    )
                    markerManager.registerEntity(entity)
                }
            }

            for entity in modifiedEntities {
                if entity.state.getAnimation() != nil {
                    MCLog.marker("AbstractMarkerController.add -> onAnimate id=\(entity.state.id)")
                    await renderer.onAnimate(entity: entity)
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func update(state: MarkerState) async {
        if markerManager.isDestroyed { return }
        MCLog.marker("AbstractMarkerController.update start id=\(state.id) anim=\(String(describing: state.getAnimation()))")
        // Match Android semantics but avoid losing the very first update when it races with the
        // initial `add(data:)` call: if an entity isn't registered yet, wait for in-flight
        // add/update work to finish once, then re-check.
        if markerManager.isDestroyed { return }
        if !markerManager.hasEntity(state.id) {
            MCLog.marker("AbstractMarkerController.update id=\(state.id) entityMissing -> waiting")
            await semaphore.withPermit { }
            if markerManager.isDestroyed { return }
            if !markerManager.hasEntity(state.id) { return }
        }

        guard let prevEntity = markerManager.getEntity(state.id) else { return }
        let currentFinger = state.fingerPrint()
        let prevFinger = prevEntity.fingerPrint
        if currentFinger == prevFinger {
            MCLog.marker("AbstractMarkerController.update id=\(state.id) fingerprintSame anim=\(String(describing: state.getAnimation()))")
            // If an animation was requested but the manager fingerprint already matches (e.g. the
            // change got "consumed" by a list-sync add()), still run the animation once.
            if state.getAnimation() != nil, !animatingMarkerIds.contains(state.id) {
                MCLog.marker("AbstractMarkerController.update id=\(state.id) -> onAnimate fallback")
                await semaphore.withPermit {
                    guard let entity = markerManager.getEntity(state.id) else { return }
                    await renderer.onAnimate(entity: entity)
                    await renderer.onPostProcess()
                }
            }
            return
        }

        let entity = MarkerEntity(
            marker: prevEntity.marker,
            state: state,
            visible: prevEntity.visible,
            isRendered: prevEntity.isRendered
        )
        markerManager.updateEntity(entity)

        await semaphore.withPermit {
            guard let marker = prevEntity.marker else { return }

            let markerIcon = (state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            let renderEntity = MarkerEntity(
                marker: marker,
                state: state,
                isRendered: true
            )
            let markerParams = MarkerOverlayChangeParams(
                current: renderEntity,
                bitmapIcon: markerIcon,
                prev: prevEntity
            )

            let markers = await renderer.onChange(data: [markerParams])
            if markers.count == 1, let actualMarker = markers[0] {
                let finalEntity = MarkerEntity(
                    marker: actualMarker,
                    state: state,
                    isRendered: true
                )
                markerManager.updateEntity(finalEntity)

                if prevFinger.animation != currentFinger.animation {
                    if state.getAnimation() != nil {
                        MCLog.marker("AbstractMarkerController.update id=\(state.id) animationChanged -> onAnimate")
                        await renderer.onAnimate(entity: finalEntity)
                    }
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func clear() async {
        if markerManager.isDestroyed { return }
        await semaphore.withPermit {
            if markerManager.isDestroyed { return }
            let entities = markerManager.allEntities()
            await renderer.onRemove(data: entities)
            markerManager.clear()
        }
    }

    open func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        // No-op for default marker flow.
    }

    open func find(position: GeoPointProtocol) -> MarkerEntity<ActualMarker>? {
        fatalError("find(position:) must be overridden by a concrete controller")
    }

    open func destroy() {
        markerManager.destroy()
    }
}
