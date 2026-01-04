public protocol OverlayControllerProtocol {
    associatedtype StateType
    associatedtype EntityType
    associatedtype EventType

    var zIndex: Int { get }

    func add(data: [StateType]) async
    func update(state: StateType) async
    func clear() async

    var clickListener: ((EventType) -> Void)? { get set }

    func find(position: GeoPointProtocol) -> EntityType?
    func onCameraChanged(mapCameraPosition: MapCameraPosition) async

    /// Cleanup resources when the controller is no longer needed.
    /// IMPORTANT: Call this when switching map providers or disposing the map.
    func destroy()
}
