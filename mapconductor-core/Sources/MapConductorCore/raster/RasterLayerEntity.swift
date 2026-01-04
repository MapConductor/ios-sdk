public protocol RasterLayerEntityProtocol {
    associatedtype ActualLayer
    var layer: ActualLayer? { get set }
    var state: RasterLayerState { get }
    var fingerPrint: RasterLayerFingerPrint { get }
}

public final class RasterLayerEntity<ActualLayer>: RasterLayerEntityProtocol {
    public var layer: ActualLayer?
    public let state: RasterLayerState
    public let fingerPrint: RasterLayerFingerPrint

    public init(layer: ActualLayer?, state: RasterLayerState) {
        self.layer = layer
        self.state = state
        self.fingerPrint = state.fingerPrint()
    }
}
