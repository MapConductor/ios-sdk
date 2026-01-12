import Foundation
import MapConductorCore

public class GoogleMapsZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    // Constants from ZoomAltitudeConverterProtocol
    private let zoomFactor: Double = 2.0
    private let minZoomLevel: Double = 0.0
    private let maxZoomLevel: Double = 22.0
    private let minAltitude: Double = 100.0
    private let maxAltitude: Double = 50_000_000.0

    public init(zoom0Altitude: Double = 171_319_879.0) {
        self.zoom0Altitude = zoom0Altitude
    }

    public func zoomLevelToAltitude(
        zoomLevel: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        // Google Maps uses direct zoom levels without altitude conversion
        // For compatibility with the unified system, we simulate altitude
        let clampedZoom = max(minZoomLevel, min(zoomLevel, maxZoomLevel))
        let altitude = zoom0Altitude / pow(zoomFactor, clampedZoom)
        return max(minAltitude, min(altitude, maxAltitude))
    }

    public func altitudeToZoomLevel(
        altitude: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        // Google Maps uses direct zoom levels without altitude conversion
        // For compatibility with the unified system, we simulate zoom from altitude
        let clampedAltitude = max(minAltitude, min(altitude, maxAltitude))
        let zoomLevel = log2(zoom0Altitude / clampedAltitude)
        return max(minZoomLevel, min(zoomLevel, maxZoomLevel))
    }
}
