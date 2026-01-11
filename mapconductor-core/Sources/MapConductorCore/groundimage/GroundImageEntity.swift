public protocol GroundImageEntityProtocol {
    associatedtype ActualGroundImage
    var groundImage: ActualGroundImage? { get set }
    var state: GroundImageState { get }
    var fingerPrint: GroundImageFingerPrint { get }
}

public final class GroundImageEntity<ActualGroundImage>: GroundImageEntityProtocol {
    public var groundImage: ActualGroundImage?
    public let state: GroundImageState
    public let fingerPrint: GroundImageFingerPrint

    public init(groundImage: ActualGroundImage?, state: GroundImageState) {
        self.groundImage = groundImage
        self.state = state
        self.fingerPrint = state.fingerPrint()
    }
}

