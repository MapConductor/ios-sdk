public protocol MarkerEntityProtocol {
    associatedtype ActualMarker

    var marker: ActualMarker? { get set }
    var state: MarkerState { get }
    var fingerPrint: MarkerFingerPrint { get }
    var visible: Bool { get set }
    var isRendered: Bool { get set }
}

public final class MarkerEntity<ActualMarker>: MarkerEntityProtocol {
    public var marker: ActualMarker?
    public let state: MarkerState
    public let fingerPrint: MarkerFingerPrint
    public var visible: Bool
    public var isRendered: Bool

    public init(
        marker: ActualMarker?,
        state: MarkerState,
        visible: Bool = true,
        isRendered: Bool = false
    ) {
        self.marker = marker
        self.state = state
        self.visible = visible
        self.isRendered = isRendered
        self.fingerPrint = state.fingerPrint()
    }
}

