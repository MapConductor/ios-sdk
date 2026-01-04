import CoreGraphics

public protocol MapViewHolderProtocol {
    associatedtype ActualMapView
    associatedtype ActualMap

    var mapView: ActualMapView { get }
    var map: ActualMap { get }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint?
    func fromScreenOffset(offset: CGPoint) async -> GeoPoint?
    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint?
}

public extension MapViewHolderProtocol {
    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}

public struct AnyMapViewHolder: MapViewHolderProtocol {
    public typealias ActualMapView = Any
    public typealias ActualMap = Any

    public let mapView: Any
    public let map: Any

    private let toScreenOffsetHandler: (GeoPointProtocol) -> CGPoint?
    private let fromScreenOffsetHandler: (CGPoint) async -> GeoPoint?
    private let fromScreenOffsetSyncHandler: (CGPoint) -> GeoPoint?

    public init<H: MapViewHolderProtocol>(_ holder: H) {
        self.mapView = holder.mapView
        self.map = holder.map
        self.toScreenOffsetHandler = { holder.toScreenOffset(position: $0) }
        self.fromScreenOffsetHandler = { offset in
            await holder.fromScreenOffset(offset: offset)
        }
        self.fromScreenOffsetSyncHandler = { holder.fromScreenOffsetSync(offset: $0) }
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        toScreenOffsetHandler(position)
    }

    public func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        await fromScreenOffsetHandler(offset)
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        fromScreenOffsetSyncHandler(offset)
    }
}
