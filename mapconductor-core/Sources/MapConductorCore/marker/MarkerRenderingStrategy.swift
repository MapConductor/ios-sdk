public protocol MarkerRenderingStrategyProtocol {
    associatedtype ActualMarker

    var markerManager: MarkerManager<ActualMarker> { get }

    func clear()

    func onAdd<Renderer: MarkerOverlayRendererProtocol>(
        data: [MarkerState],
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker

    func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
        state: MarkerState,
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker

    func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
        mapCameraPosition: MapCameraPosition,
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker
}

public struct AnyMarkerRenderingStrategy<ActualMarker>: MarkerRenderingStrategyProtocol {
    public let markerManager: MarkerManager<ActualMarker>
    private let clearHandler: () -> Void
    private let onAddHandler: ([MarkerState], GeoRectBounds, AnyMarkerOverlayRenderer<ActualMarker>) async -> Bool
    private let onUpdateHandler: (MarkerState, GeoRectBounds, AnyMarkerOverlayRenderer<ActualMarker>) async -> Bool
    private let onCameraChangedHandler: (MapCameraPosition, AnyMarkerOverlayRenderer<ActualMarker>) async -> Void

    public init<Strategy: MarkerRenderingStrategyProtocol>(_ strategy: Strategy) where Strategy.ActualMarker == ActualMarker {
        self.markerManager = strategy.markerManager
        self.clearHandler = { strategy.clear() }
        self.onAddHandler = { data, viewport, renderer in
            await strategy.onAdd(data: data, viewport: viewport, renderer: renderer)
        }
        self.onUpdateHandler = { state, viewport, renderer in
            await strategy.onUpdate(state: state, viewport: viewport, renderer: renderer)
        }
        self.onCameraChangedHandler = { cameraPosition, renderer in
            await strategy.onCameraChanged(mapCameraPosition: cameraPosition, renderer: renderer)
        }
    }

    public func clear() {
        clearHandler()
    }

    public func onAdd<Renderer: MarkerOverlayRendererProtocol>(
        data: [MarkerState],
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        await onAddHandler(data, viewport, AnyMarkerOverlayRenderer(renderer))
    }

    public func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
        state: MarkerState,
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        await onUpdateHandler(state, viewport, AnyMarkerOverlayRenderer(renderer))
    }

    public func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
        mapCameraPosition: MapCameraPosition,
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker {
        await onCameraChangedHandler(mapCameraPosition, AnyMarkerOverlayRenderer(renderer))
    }
}

public struct AnyMarkerOverlayRenderer<ActualMarker>: MarkerOverlayRendererProtocol {
    public var animateStartListener: OnMarkerEventHandler? {
        get { getAnimateStart() }
        set { setAnimateStart(newValue) }
    }

    public var animateEndListener: OnMarkerEventHandler? {
        get { getAnimateEnd() }
        set { setAnimateEnd(newValue) }
    }

    private let getAnimateStart: () -> OnMarkerEventHandler?
    private let setAnimateStart: (OnMarkerEventHandler?) -> Void
    private let getAnimateEnd: () -> OnMarkerEventHandler?
    private let setAnimateEnd: (OnMarkerEventHandler?) -> Void
    private let onAddHandler: ([MarkerOverlayAddParams]) async -> [ActualMarker?]
    private let onChangeHandler: ([MarkerOverlayChangeParams<ActualMarker>]) async -> [ActualMarker?]
    private let onRemoveHandler: ([MarkerEntity<ActualMarker>]) async -> Void
    private let onAnimateHandler: (MarkerEntity<ActualMarker>) async -> Void
    private let onPostProcessHandler: () async -> Void

    public init<Renderer: MarkerOverlayRendererProtocol>(_ renderer: Renderer) where Renderer.ActualMarker == ActualMarker {
        var mutableRenderer = renderer
        self.getAnimateStart = { mutableRenderer.animateStartListener }
        self.setAnimateStart = { mutableRenderer.animateStartListener = $0 }
        self.getAnimateEnd = { mutableRenderer.animateEndListener }
        self.setAnimateEnd = { mutableRenderer.animateEndListener = $0 }
        self.onAddHandler = { data in
            await mutableRenderer.onAdd(data: data)
        }
        self.onChangeHandler = { data in
            await mutableRenderer.onChange(data: data)
        }
        self.onRemoveHandler = { data in
            await mutableRenderer.onRemove(data: data)
        }
        self.onAnimateHandler = { entity in
            await mutableRenderer.onAnimate(entity: entity)
        }
        self.onPostProcessHandler = {
            await mutableRenderer.onPostProcess()
        }
    }

    public func onAdd(data: [MarkerOverlayAddParams]) async -> [ActualMarker?] {
        await onAddHandler(data)
    }

    public func onChange(data: [MarkerOverlayChangeParams<ActualMarker>]) async -> [ActualMarker?] {
        await onChangeHandler(data)
    }

    public func onRemove(data: [MarkerEntity<ActualMarker>]) async {
        await onRemoveHandler(data)
    }

    public func onAnimate(entity: MarkerEntity<ActualMarker>) async {
        await onAnimateHandler(entity)
    }

    public func onPostProcess() async {
        await onPostProcessHandler()
    }
}

open class AbstractMarkerRenderingStrategy<ActualMarker>: MarkerRenderingStrategyProtocol {
    public let markerManager: MarkerManager<ActualMarker>
    public let semaphore: AsyncSemaphore
    public let defaultMarkerIcon: BitmapIcon

    public init(
        markerManager: MarkerManager<ActualMarker> = MarkerManager<ActualMarker>(),
        semaphore: AsyncSemaphore = AsyncSemaphore(1)
    ) {
        self.markerManager = markerManager
        self.semaphore = semaphore
        self.defaultMarkerIcon = DefaultMarkerIcon().toBitmapIcon()
    }

    open func clear() {
        markerManager.clear()
    }

    open func onAdd<Renderer: MarkerOverlayRendererProtocol>(
        data: [MarkerState],
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        false
    }

    open func onUpdate<Renderer: MarkerOverlayRendererProtocol>(
        state: MarkerState,
        viewport: GeoRectBounds,
        renderer: Renderer
    ) async -> Bool where Renderer.ActualMarker == ActualMarker {
        false
    }

    open func onCameraChanged<Renderer: MarkerOverlayRendererProtocol>(
        mapCameraPosition: MapCameraPosition,
        renderer: Renderer
    ) async where Renderer.ActualMarker == ActualMarker {
    }
}
