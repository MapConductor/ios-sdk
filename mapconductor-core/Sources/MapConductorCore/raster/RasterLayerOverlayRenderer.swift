public protocol RasterLayerOverlayRendererProtocol {
    associatedtype ActualLayer

    func onAdd(data: [RasterLayerOverlayAddParams]) async -> [ActualLayer?]
    func onChange(data: [RasterLayerOverlayChangeParams<ActualLayer>]) async -> [ActualLayer?]
    func onRemove(data: [RasterLayerEntity<ActualLayer>]) async
    func onCameraChanged(mapCameraPosition: MapCameraPosition) async
    func onPostProcess() async
}

public extension RasterLayerOverlayRendererProtocol {
    func onCameraChanged(mapCameraPosition: MapCameraPosition) async {}
}

open class AbstractRasterLayerOverlayRenderer<ActualLayer>: RasterLayerOverlayRendererProtocol {
    public init() {}

    open func onPostProcess() async {}

    open func createLayer(state: RasterLayerState) async -> ActualLayer? {
        fatalError("Override in subclass")
    }

    open func updateLayerProperties(
        layer: ActualLayer,
        current: RasterLayerEntity<ActualLayer>,
        prev: RasterLayerEntity<ActualLayer>
    ) async -> ActualLayer? {
        fatalError("Override in subclass")
    }

    open func removeLayer(entity: RasterLayerEntity<ActualLayer>) async {
        fatalError("Override in subclass")
    }

    public func onAdd(data: [RasterLayerOverlayAddParams]) async -> [ActualLayer?] {
        var results: [ActualLayer?] = []
        results.reserveCapacity(data.count)
        for params in data {
            results.append(await createLayer(state: params.state))
        }
        return results
    }

    public func onChange(data: [RasterLayerOverlayChangeParams<ActualLayer>]) async -> [ActualLayer?] {
        var results: [ActualLayer?] = []
        results.reserveCapacity(data.count)
        for params in data {
            guard let layer = params.prev.layer else {
                results.append(nil)
                continue
            }
            results.append(
                await updateLayerProperties(
                    layer: layer,
                    current: params.current,
                    prev: params.prev
                )
            )
        }
        return results
    }

    public func onRemove(data: [RasterLayerEntity<ActualLayer>]) async {
        for entity in data {
            await removeLayer(entity: entity)
        }
    }
}

public struct RasterLayerOverlayAddParams {
    public let state: RasterLayerState

    public init(state: RasterLayerState) {
        self.state = state
    }
}

public struct RasterLayerOverlayChangeParams<ActualLayer> {
    public let current: RasterLayerEntity<ActualLayer>
    public let prev: RasterLayerEntity<ActualLayer>

    public init(current: RasterLayerEntity<ActualLayer>, prev: RasterLayerEntity<ActualLayer>) {
        self.current = current
        self.prev = prev
    }
}
