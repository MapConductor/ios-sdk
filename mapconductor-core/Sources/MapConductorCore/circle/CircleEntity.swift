public protocol CircleEntityProtocol {
    associatedtype ActualCircle
    var circle: ActualCircle? { get set }
    var state: CircleState { get }
    var fingerPrint: CircleFingerPrint { get }
}

public final class CircleEntity<ActualCircle>: CircleEntityProtocol {
    public var circle: ActualCircle?
    public let state: CircleState
    public let fingerPrint: CircleFingerPrint

    public init(circle: ActualCircle?, state: CircleState) {
        self.circle = circle
        self.state = state
        self.fingerPrint = state.fingerPrint()
    }
}
