open class RasterLayerController<ActualLayer, Renderer: RasterLayerOverlayRendererProtocol>: OverlayControllerProtocol
where Renderer.ActualLayer == ActualLayer {
    public typealias StateType = RasterLayerState
    public typealias EntityType = RasterLayerEntity<ActualLayer>
    public typealias EventType = RasterLayerEvent

    public let rasterLayerManager: RasterLayerManager<ActualLayer>
    open var renderer: Renderer

    public let zIndex: Int = 0
    private let semaphore = AsyncSemaphore(1)

    public var clickListener: ((RasterLayerEvent) -> Void)?

    public init(
        rasterLayerManager: RasterLayerManager<ActualLayer>,
        renderer: Renderer,
        clickListener: ((RasterLayerEvent) -> Void)? = nil
    ) {
        self.rasterLayerManager = rasterLayerManager
        self.renderer = renderer
        self.clickListener = clickListener
    }

    public func dispatchClick(event: RasterLayerEvent) {
        clickListener?(event)
    }

    open func add(data: [RasterLayerState]) async {
        if rasterLayerManager.isDestroyed { return }
        await semaphore.withPermit {
            if rasterLayerManager.isDestroyed { return }
            var previous = Set(rasterLayerManager.allEntities().map { $0.state.id })
            var added: [RasterLayerOverlayAddParams] = []
            var updated: [RasterLayerOverlayChangeParams<ActualLayer>] = []
            var removed: [RasterLayerEntity<ActualLayer>] = []

            for state in data {
                if previous.contains(state.id), let prevEntity = rasterLayerManager.getEntity(state.id) {
                    updated.append(
                        RasterLayerOverlayChangeParams(
                            current: RasterLayerEntity(layer: prevEntity.layer, state: state),
                            prev: prevEntity
                        )
                    )
                    previous.remove(state.id)
                } else {
                    added.append(RasterLayerOverlayAddParams(state: state))
                    previous.remove(state.id)
                }
            }

            for remainId in previous {
                if let removedEntity = rasterLayerManager.removeEntity(remainId) {
                    removed.append(removedEntity)
                }
            }

            if !removed.isEmpty {
                await renderer.onRemove(data: removed)
            }

            if !added.isEmpty {
                let actualLayers = await renderer.onAdd(data: added)
                for (index, layer) in actualLayers.enumerated() {
                    guard let layer else { continue }
                    let entity = RasterLayerEntity(layer: layer, state: added[index].state)
                    rasterLayerManager.registerEntity(entity)
                }
            }

            if !updated.isEmpty {
                let actualLayers = await renderer.onChange(data: updated)
                for (index, layer) in actualLayers.enumerated() {
                    guard let layer else { continue }
                    let params = updated[index]
                    let entity = RasterLayerEntity(layer: layer, state: params.current.state)
                    rasterLayerManager.registerEntity(entity)
                }
            }

            await renderer.onPostProcess()
        }
    }

    open func update(state: RasterLayerState) async {
        if rasterLayerManager.isDestroyed { return }
        await semaphore.withPermit {
            guard let prevEntity = rasterLayerManager.getEntity(state.id) else { return }
            let currentFinger = state.fingerPrint()
            let prevFinger = prevEntity.fingerPrint
            if currentFinger == prevFinger { return }

            let entity = RasterLayerEntity(layer: prevEntity.layer, state: state)
            let params = RasterLayerOverlayChangeParams(current: entity, prev: prevEntity)
            let layers = await renderer.onChange(data: [params])

            if layers.count == 1, let actualLayer = layers[0] {
                let updated = RasterLayerEntity(layer: actualLayer, state: state)
                rasterLayerManager.registerEntity(updated)
            }

            await renderer.onPostProcess()
        }
    }

    open func clear() async {
        if rasterLayerManager.isDestroyed { return }
        await semaphore.withPermit {
            let entities = rasterLayerManager.allEntities()
            await renderer.onRemove(data: entities)
            await renderer.onPostProcess()
            rasterLayerManager.clear()
        }
    }

    open func find(position: GeoPointProtocol) -> RasterLayerEntity<ActualLayer>? {
        nil
    }

    open func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        await renderer.onCameraChanged(mapCameraPosition: mapCameraPosition)
    }

    open func destroy() {
        rasterLayerManager.destroy()
    }
}
