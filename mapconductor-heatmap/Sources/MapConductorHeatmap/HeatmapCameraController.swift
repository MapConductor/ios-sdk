import MapConductorCore

public final class HeatmapCameraController: OverlayControllerProtocol {
    public typealias StateType = Void
    public typealias EntityType = Void
    public typealias EventType = Void

    public let zIndex: Int = 0
    public var clickListener: ((Void) -> Void)?

    private let renderer: HeatmapTileRenderer

    public init(renderer: HeatmapTileRenderer) {
        self.renderer = renderer
    }

    public func add(data: [Void]) async {}

    public func update(state: Void) async {}

    public func clear() async {}

    public func find(position: GeoPointProtocol) -> Void? {
        nil
    }

    public func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        renderer.updateCameraZoom(mapCameraPosition.zoom)
    }

    public func destroy() {
        // No native resources to clean up.
    }
}
