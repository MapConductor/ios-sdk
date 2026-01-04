import Foundation

public protocol GeoPointProtocol {
    func wrap() -> GeoPointProtocol

    var latitude: Double { get }
    var longitude: Double { get }
    var altitude: Double? { get }
}

public struct GeoPoint: GeoPointProtocol, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double
    private let altitudeValue: Double

    public var altitude: Double? { altitudeValue }

    public init(latitude: Double, longitude: Double, altitude: Double = 0.0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeValue = altitude
    }

    public func toUrlValue(precision: Int = 6) -> String {
        "\(latitude.toFixed(precision)),\(longitude.toFixed(precision))"
    }

    public static func == (lhs: GeoPoint, rhs: GeoPoint) -> Bool {
        let tolerance = 1e-7
        return abs(lhs.latitude - rhs.latitude) < tolerance &&
            abs(lhs.longitude - rhs.longitude) < tolerance &&
            abs(lhs.altitudeValue - rhs.altitudeValue) < tolerance
    }

    public func hash(into hasher: inout Hasher) {
        let latHash = Int64(latitude * 1e7)
        let lngHash = Int64(longitude * 1e7)
        let altHash = Int64(altitudeValue * 1e7)

        hasher.combine(latHash)
        hasher.combine(lngHash)
        hasher.combine(altHash)
    }

    public func wrap() -> GeoPointProtocol {
        var wrappedLatitude = latitude
        var wrappedLongitude = longitude

        if wrappedLatitude > 90.0 {
            let excess = wrappedLatitude - 90.0
            wrappedLatitude = -90.0 + excess
            wrappedLongitude += 180.0
        } else if wrappedLatitude < -90.0 {
            let deficit = -90.0 - wrappedLatitude
            wrappedLatitude = 90.0 - deficit
            wrappedLongitude += 180.0
        }

        wrappedLongitude = (((wrappedLongitude + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) - 180

        return GeoPoint(latitude: wrappedLatitude, longitude: wrappedLongitude, altitude: altitudeValue)
    }

    public static func fromLatLong(
        latitude: Double,
        longitude: Double
    ) -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }

    public static func fromLongLat(
        longitude: Double,
        latitude: Double
    ) -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }

    public static func from(position: GeoPointProtocol) -> GeoPoint {
        if let impl = position as? GeoPoint {
            return impl
        }
        return GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude ?? 0.0
        )
    }
}

public extension GeoPointProtocol {
    func normalize() -> GeoPoint {
        GeoPoint(
            latitude: min(max(latitude, -90.0), 90.0),
            longitude: (((longitude + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) - 180,
            altitude: altitude ?? 0.0
        )
    }

    func isValid() -> Bool {
        latitude >= -90.0 && latitude <= 90.0 && longitude >= -180.0 && longitude <= 180.0
    }
}

private extension Double {
    func toFixed(_ precision: Int) -> String {
        String(format: "%.\(precision)f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}
