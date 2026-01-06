import MapConductorCore

public struct MarkerClusterDebugInfo: Equatable, Hashable {
    public let id: String
    public let center: GeoPoint
    public let radiusMeters: Double
    public let count: Int

    public init(
        id: String,
        center: GeoPoint,
        radiusMeters: Double,
        count: Int
    ) {
        self.id = id
        self.center = center
        self.radiusMeters = radiusMeters
        self.count = count
    }
}
