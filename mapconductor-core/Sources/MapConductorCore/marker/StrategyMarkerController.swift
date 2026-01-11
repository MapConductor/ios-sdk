public final class StrategyMarkerController<ActualMarker, Strategy: MarkerRenderingStrategyProtocol, Renderer: MarkerOverlayRendererProtocol>: OverlayControllerProtocol
where Strategy.ActualMarker == ActualMarker, Renderer.ActualMarker == ActualMarker {
    public typealias StateType = MarkerState
    public typealias EntityType = MarkerEntity<ActualMarker>
    public typealias EventType = MarkerState

    public let markerManager: MarkerManager<ActualMarker>
    public let strategy: Strategy
    public var renderer: Renderer
    public var clickListener: ((MarkerState) -> Void)?

    public var dragStartListener: OnMarkerEventHandler?
    public var dragListener: OnMarkerEventHandler?
    public var dragEndListener: OnMarkerEventHandler?
    public var animateStartListener: OnMarkerEventHandler?
    public var animateEndListener: OnMarkerEventHandler?

    public let zIndex: Int = 10
    private let semaphore = AsyncSemaphore(1)
    private var mapCameraPosition: MapCameraPosition?
    private var pendingStates: [MarkerState]?

    public init(
        strategy: Strategy,
        renderer: Renderer,
        clickListener: ((MarkerState) -> Void)? = nil
    ) {
        self.strategy = strategy
        self.renderer = renderer
        self.markerManager = strategy.markerManager
        self.clickListener = clickListener

        Task { @MainActor in
            self.renderer.animateStartListener = { [weak self] state in
                self?.dispatchAnimateStart(state)
            }
            self.renderer.animateEndListener = { [weak self] state in
                self?.dispatchAnimateEnd(state)
            }
        }
    }

    public func dispatchClick(_ state: MarkerState) {
        state.onClick?(state)
        clickListener?(state)
    }

    public func dispatchDragStart(_ state: MarkerState) {
        state.onDragStart?(state)
        dragStartListener?(state)
    }

    public func dispatchDrag(_ state: MarkerState) {
        state.onDrag?(state)
        dragListener?(state)
    }

    public func dispatchDragEnd(_ state: MarkerState) {
        state.onDragEnd?(state)
        dragEndListener?(state)
    }

    public func dispatchAnimateStart(_ state: MarkerState) {
        state.onAnimateStart?(state)
        animateStartListener?(state)
    }

    public func dispatchAnimateEnd(_ state: MarkerState) {
        state.onAnimateEnd?(state)
        animateEndListener?(state)
    }

    public func add(data: [MarkerState]) async {
        guard let bounds = mapCameraPosition?.visibleRegion?.bounds else {
            pendingStates = data
            return
        }
        await semaphore.withPermit {
            _ = await strategy.onAdd(
                data: data,
                viewport: bounds,
                renderer: renderer
            )
        }
    }

    public func update(state: MarkerState) async {
        guard let bounds = mapCameraPosition?.visibleRegion?.bounds else { return }
        await semaphore.withPermit {
            _ = await strategy.onUpdate(
                state: state,
                viewport: bounds,
                renderer: renderer
            )
        }
    }

    public func clear() async {
        strategy.clear()
    }

    public func find(position: GeoPointProtocol) -> MarkerEntity<ActualMarker>? {
        markerManager.findNearest(position: position)
    }

    public func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        self.mapCameraPosition = mapCameraPosition
        await semaphore.withPermit {
            await strategy.onCameraChanged(
                mapCameraPosition: mapCameraPosition,
                renderer: renderer
            )
        }

        if let pending = pendingStates {
            pendingStates = nil
            await add(data: pending)
        }
    }

    public func destroy() {
        strategy.clear()
    }
}
