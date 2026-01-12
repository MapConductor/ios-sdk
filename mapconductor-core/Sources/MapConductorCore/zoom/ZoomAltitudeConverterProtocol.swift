import Foundation

public protocol ZoomAltitudeConverterProtocol {
    var zoom0Altitude: Double { get }

    func zoomLevelToAltitude(
        zoomLevel: Double,
        latitude: Double,
        tilt: Double
    ) -> Double

    func altitudeToZoomLevel(
        altitude: Double,
        latitude: Double,
        tilt: Double
    ) -> Double
}

public extension ZoomAltitudeConverterProtocol {
    static var defaultZoom0Altitude: Double { 171_319_879.0 } // Calibrated to match Google Maps visible regions
    static var zoomFactor: Double { 2.0 }
    static var minZoomLevel: Double { 0.0 }
    static var maxZoomLevel: Double { 22.0 }
    static var minAltitude: Double { 100.0 }
    static var maxAltitude: Double { 50_000_000.0 }
    static var minCosLat: Double { 0.01 }
    static var minCosTilt: Double { 0.05 }
    static var webMercatorInitialMpp256: Double { 156_543.033_928 }
}
