public protocol PolylineEntityProtocol {
    associatedtype ActualPolyline
    var polyline: ActualPolyline? { get set }
    var state: PolylineState { get }
    var fingerPrint: PolylineFingerPrint { get }
}

public final class PolylineEntity<ActualPolyline>: PolylineEntityProtocol {
    public var polyline: ActualPolyline?
    public let state: PolylineState
    public let fingerPrint: PolylineFingerPrint

    public init(
        polyline: ActualPolyline?,
        state: PolylineState
    ) {
        self.polyline = polyline
        self.state = state
        self.fingerPrint = state.fingerPrint()
    }
}
