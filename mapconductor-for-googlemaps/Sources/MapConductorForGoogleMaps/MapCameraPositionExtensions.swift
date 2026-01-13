import Foundation
import GoogleMaps
import MapConductorCore

private let converter = GoogleMapsZoomAltitudeConverter(zoom0Altitude: 171_319_879.0)

// Convert from MapCameraPosition to GMSCameraPosition
public extension MapCameraPosition {
    func toCameraPosition() -> GMSCameraPosition {
        GMSCameraPosition(
            latitude: position.latitude,
            longitude: position.longitude,
            zoom: Float(zoom),
            bearing: bearing,
            viewingAngle: tilt
        )
    }
}

// Convert from GMSCameraPosition to MapCameraPosition
public extension GMSCameraPosition {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition {
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: Double(zoom),
            latitude: target.latitude,
            tilt: Double(viewingAngle)
        )
        let position = GeoPoint(
            latitude: target.latitude,
            longitude: target.longitude,
            altitude: altitude
        )
        return MapCameraPosition(
            position: position,
            zoom: Double(zoom),
            bearing: bearing,
            tilt: viewingAngle,
            visibleRegion: visibleRegion
        )
    }
}
