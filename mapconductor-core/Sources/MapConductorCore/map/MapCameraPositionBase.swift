import Foundation

public struct VisibleRegion: Equatable, Hashable {
    public let bounds: GeoRectBounds
    public let nearLeft: GeoPoint?
    public let nearRight: GeoPoint?
    public let farLeft: GeoPoint?
    public let farRight: GeoPoint?

    public init(
        bounds: GeoRectBounds,
        nearLeft: GeoPoint? = nil,
        nearRight: GeoPoint? = nil,
        farLeft: GeoPoint? = nil,
        farRight: GeoPoint? = nil
    ) {
        self.bounds = bounds
        self.nearLeft = nearLeft
        self.nearRight = nearRight
        self.farLeft = farLeft
        self.farRight = farRight
    }

    public static func == (lhs: VisibleRegion, rhs: VisibleRegion) -> Bool {
        lhs.bounds == rhs.bounds &&
            geoPointEquals(lhs.nearLeft, rhs.nearLeft) &&
            geoPointEquals(lhs.nearRight, rhs.nearRight) &&
            geoPointEquals(lhs.farLeft, rhs.farLeft) &&
            geoPointEquals(lhs.farRight, rhs.farRight)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bounds)
        hasher.combine(geoPointHash(nearLeft))
        hasher.combine(geoPointHash(nearRight))
        hasher.combine(geoPointHash(farLeft))
        hasher.combine(geoPointHash(farRight))
    }
}

public protocol MapCameraPositionProtocol {
    var position: GeoPointProtocol { get }
    var zoom: Double { get }
    var bearing: Double { get }
    var tilt: Double { get }
    var paddings: MapPaddingsProtocol? { get }
    var visibleRegion: VisibleRegion? { get }
}

public final class MapCameraPosition: MapCameraPositionProtocol {
    public var position: GeoPointProtocol { positionValue }
    public let zoom: Double
    public let bearing: Double
    public let tilt: Double
    public let paddings: MapPaddingsProtocol?
    public let visibleRegion: VisibleRegion?
    private let positionValue: GeoPoint

    public init(
        position: GeoPointProtocol,
        zoom: Double = 0.0,
        bearing: Double = 0.0,
        tilt: Double = 0.0,
        paddings: MapPaddingsProtocol? = MapPaddings.Zeros,
        visibleRegion: VisibleRegion? = nil
    ) {
        self.positionValue = GeoPoint.from(position: position)
        self.zoom = zoom
        self.bearing = bearing
        self.tilt = tilt
        self.paddings = paddings
        self.visibleRegion = visibleRegion
    }

    public func equals(other: MapCameraPositionProtocol) -> Bool {
        positionValue == GeoPoint.from(position: other.position) &&
            zoomEquals(other) &&
            bearingEquals(other) &&
            tiltEquals(other)
    }

    public func copy(
        position: GeoPointProtocol? = nil,
        zoom: Double? = nil,
        bearing: Double? = nil,
        tilt: Double? = nil,
        paddings: MapPaddingsProtocol? = nil,
        visibleRegion: VisibleRegion? = nil
    ) -> MapCameraPosition {
        MapCameraPosition(
            position: position ?? self.positionValue,
            zoom: zoom ?? self.zoom,
            bearing: bearing ?? self.bearing,
            tilt: tilt ?? self.tilt,
            paddings: paddings ?? self.paddings,
            visibleRegion: visibleRegion ?? self.visibleRegion
        )
    }

    private func zoomEquals(_ other: MapCameraPositionProtocol) -> Bool {
        let tolerance = 1e-2
        return abs(zoom - other.zoom) < tolerance
    }

    private func bearingEquals(_ other: MapCameraPositionProtocol) -> Bool {
        let tolerance = 1e-2
        return abs(bearing - other.bearing) < tolerance
    }

    private func tiltEquals(_ other: MapCameraPositionProtocol) -> Bool {
        let tolerance = 1e-2
        return abs(tilt - other.tilt) < tolerance
    }

    public func hashCode() -> Int {
        var result = positionValue.hashValue
        result = 31 * result + zoom.hashValue
        result = 31 * result + bearing.hashValue
        result = 31 * result + tilt.hashValue
        let paddingHash = paddings.map { MapPaddings.from(paddings: $0).hashCode() } ?? 0
        result = 31 * result + paddingHash
        result = 31 * result + (visibleRegion?.hashValue ?? 0)
        return result
    }

    public static let Default = MapCameraPosition(
        position: GeoPoint(latitude: 0.0, longitude: 0.0, altitude: 0.0),
        zoom: 0.0,
        bearing: 0.0,
        tilt: 0.0
    )
}

private func geoPointEquals(_ lhs: GeoPoint?, _ rhs: GeoPoint?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        return true
    case (let left?, let right?):
        return left == right
    default:
        return false
    }
}

private func geoPointHash(_ point: GeoPoint?) -> GeoPoint? {
    point
}
