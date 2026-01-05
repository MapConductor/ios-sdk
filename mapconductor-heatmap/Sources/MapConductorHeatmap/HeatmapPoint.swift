import MapConductorCore

public struct HeatmapPoint: Hashable {
    public let position: GeoPoint
    public let weight: Double

    public init(position: GeoPoint, weight: Double) {
        self.position = position
        self.weight = weight
    }
}
