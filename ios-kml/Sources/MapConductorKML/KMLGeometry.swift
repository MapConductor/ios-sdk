import Foundation

public struct LonLat: Equatable, Hashable {
    public let longitude: Double
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

public indirect enum KMLGeometry: Equatable, Hashable {
    case point(longitude: Double, latitude: Double)
    case multiPoint(points: [LonLat])
    case lineString(coordinates: [LonLat])
    case multiLineString(lines: [[LonLat]])
    /// Polygon rings in KML order: first ring is the exterior (outerBoundaryIs),
    /// subsequent rings are holes (innerBoundaryIs).
    case polygon(rings: [[LonLat]])
    case multiPolygon(polygons: [[[LonLat]]])
    /// Represents a KML `<MultiGeometry>` — an unordered collection of heterogeneous geometries.
    case geometryCollection(geometries: [KMLGeometry])
    case empty
}
