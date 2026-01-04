import Combine
import Foundation

public enum InitState {
    case NotStarted
    case Initializing
    case SdkInitialized
    case MapViewCreated
    case MapCreated
    case Failed
}

public protocol MapViewStateProtocol: ObservableObject {
    associatedtype ActualMapDesignType

    var id: String { get }
    var cameraPosition: MapCameraPosition { get }
    var mapDesignType: ActualMapDesignType { get set }

    func moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?)
    func moveCameraTo(position: GeoPoint, durationMillis: Long?)

    func getMapViewHolder() -> AnyMapViewHolder?
}

public extension MapViewStateProtocol {
    func moveCameraTo(cameraPosition: MapCameraPosition) {
        moveCameraTo(cameraPosition: cameraPosition, durationMillis: 0)
    }

    func moveCameraTo(position: GeoPoint) {
        moveCameraTo(position: position, durationMillis: 0)
    }
}

open class MapViewState<ActualMapDesignType>: ObservableObject, MapViewStateProtocol {
    public init() {}

    open var id: String {
        fatalError("Override in subclass")
    }

    open var cameraPosition: MapCameraPosition {
        fatalError("Override in subclass")
    }

    open var mapDesignType: ActualMapDesignType {
        get { fatalError("Override in subclass") }
        set { fatalError("Override in subclass") }
    }

    open func moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long?) {
        fatalError("Override in subclass")
    }

    open func moveCameraTo(position: GeoPoint, durationMillis: Long?) {
        let updated = cameraPosition.copy(position: position)
        moveCameraTo(cameraPosition: updated, durationMillis: durationMillis)
    }

    open func getMapViewHolder() -> AnyMapViewHolder? {
        fatalError("Override in subclass")
    }
}

public protocol MapOverlayProtocol: AnyObject {
    associatedtype DataType

    var flow: CurrentValueSubject<[String: DataType], Never> { get }

    func render(
        data: [String: DataType],
        controller: MapViewControllerProtocol
    ) async
}

public final class MapOverlayRegistry {
    private var overlays: [any MapOverlayProtocol] = []

    public init() {}

    public func register(overlay: any MapOverlayProtocol) {
        if overlays.contains(where: { $0 === overlay }) { return }
        overlays.append(overlay)
    }

    public func getAll() -> [any MapOverlayProtocol] {
        overlays
    }
}
