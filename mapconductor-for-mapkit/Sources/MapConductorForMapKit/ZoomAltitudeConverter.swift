import Foundation
import MapConductorCore

public class MapKitZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    // Constants from ZoomAltitudeConverterProtocol
    private let minZoomLevel: Double = 0.0
    private let maxZoomLevel: Double = 22.0
    private let minAltitude: Double = 100.0
    private let maxAltitude: Double = 50_000_000.0
    private let minCosLat: Double = 0.01
    private let minCosTilt: Double = 0.05

    public init(zoom0Altitude: Double = 190_319_879.0) {
        self.zoom0Altitude = zoom0Altitude
    }

    public func zoomLevelToAltitude(
        zoomLevel: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        // MapKit uses altitude (camera distance) to control zoom
        // Formula (distance): distance = zoom0Altitude * cos(latitude) / (2^zoom)
        // MKMapCamera.altitude is the vertical component, and MKMapCamera(…fromDistance:) uses the slant distance.
        // So: altitude = distance * cos(tilt)
        let clampedZoom = max(minZoomLevel, min(zoomLevel, maxZoomLevel))

        let clampedLat = max(-85.0, min(latitude, 85.0))
        let latitudeRadians = clampedLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let clampedTilt = max(0.0, min(tilt, 90.0))
        let tiltRadians = clampedTilt * .pi / 180.0
        let cosTilt = max(cos(tiltRadians), minCosTilt)

        let distance = (zoom0Altitude * cosLat) / pow(2.0, clampedZoom)
        let altitude = distance * cosTilt

        return max(minAltitude, min(altitude, maxAltitude))
    }

    public func altitudeToZoomLevel(
        altitude: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        // Convert altitude back to zoom level
        // Formula:
        // distance = altitude / cos(tilt)
        // zoom = log2(zoom0Altitude * cos(latitude) / distance)
        let clampedAltitude = max(minAltitude, min(altitude, maxAltitude))

        let clampedLat = max(-85.0, min(latitude, 85.0))
        let latitudeRadians = clampedLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let clampedTilt = max(0.0, min(tilt, 90.0))
        let tiltRadians = clampedTilt * .pi / 180.0
        let cosTilt = max(cos(tiltRadians), minCosTilt)

        let distance = clampedAltitude / cosTilt
        let zoomLevel = log2((zoom0Altitude * cosLat) / distance)

        return max(minZoomLevel, min(zoomLevel, maxZoomLevel))
    }
}
