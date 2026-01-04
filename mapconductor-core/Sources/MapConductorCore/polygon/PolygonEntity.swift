public protocol PolygonEntityProtocol {
    associatedtype ActualPolygon
    var polygon: ActualPolygon? { get set }
    var state: PolygonState { get }
    var fingerPrint: PolygonFingerPrint { get }
}

public final class PolygonEntity<ActualPolygon>: PolygonEntityProtocol {
    public var polygon: ActualPolygon?
    public let state: PolygonState
    public let fingerPrint: PolygonFingerPrint

    public init(polygon: ActualPolygon?, state: PolygonState) {
        self.polygon = polygon
        self.state = state
        self.fingerPrint = state.fingerPrint()
    }
}
