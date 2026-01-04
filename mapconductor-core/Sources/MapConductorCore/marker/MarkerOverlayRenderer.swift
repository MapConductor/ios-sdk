@MainActor
public protocol MarkerOverlayRendererProtocol {
    associatedtype ActualMarker

    var animateStartListener: OnMarkerEventHandler? { get set }
    var animateEndListener: OnMarkerEventHandler? { get set }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [ActualMarker?]
    func onChange(data: [MarkerOverlayChangeParams<ActualMarker>]) async -> [ActualMarker?]
    func onRemove(data: [MarkerEntity<ActualMarker>]) async
    func onAnimate(entity: MarkerEntity<ActualMarker>) async
    func onPostProcess() async
}

public struct MarkerOverlayAddParams {
    public let state: MarkerState
    public let bitmapIcon: BitmapIcon

    public init(state: MarkerState, bitmapIcon: BitmapIcon) {
        self.state = state
        self.bitmapIcon = bitmapIcon
    }
}

public struct MarkerOverlayChangeParams<ActualMarker> {
    public let current: MarkerEntity<ActualMarker>
    public let bitmapIcon: BitmapIcon
    public let prev: MarkerEntity<ActualMarker>

    public init(
        current: MarkerEntity<ActualMarker>,
        bitmapIcon: BitmapIcon,
        prev: MarkerEntity<ActualMarker>
    ) {
        self.current = current
        self.bitmapIcon = bitmapIcon
        self.prev = prev
    }
}
