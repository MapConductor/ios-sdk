import CoreGraphics
import Foundation

public protocol ProjectionProtocol: Sendable {
    func project(_ point: GeoPointProtocol) -> CGPoint
    func unproject(_ point: CGPoint) -> GeoPoint
}

/// Web Mercator projection where projected coordinates are meters in EPSG:3857.
public struct WebMercatorProjection: ProjectionProtocol {
    public init() {}

    public func project(_ point: GeoPointProtocol) -> CGPoint {
        let wrapped = GeoPoint.from(position: point).wrap()
        let latitude = GeoPoint.from(position: wrapped).latitude
        let longitude = GeoPoint.from(position: wrapped).longitude

        let x = Earth.radiusMeters * deg2rad(longitude)

        // Clamp latitude to avoid infinity at the poles.
        let clampedLat = min(max(latitude, -85.05112878), 85.05112878)
        let latRad = deg2rad(clampedLat)
        let y = Earth.radiusMeters * log(tan(.pi / 4.0 + latRad / 2.0))

        return CGPoint(x: x, y: y)
    }

    public func unproject(_ point: CGPoint) -> GeoPoint {
        let longitude = rad2deg(point.x / Earth.radiusMeters)
        let latitude = rad2deg(2.0 * atan(exp(point.y / Earth.radiusMeters)) - .pi / 2.0)
        return GeoPoint.from(position: GeoPoint(latitude: latitude, longitude: longitude).wrap())
    }
}

private func deg2rad(_ degrees: Double) -> Double { degrees * .pi / 180.0 }
private func rad2deg(_ radians: Double) -> Double { radians * 180.0 / .pi }
