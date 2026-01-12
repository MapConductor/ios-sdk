import Foundation
import MapKit
import MapConductorCore

private let converter = MapKitZoomAltitudeConverter(zoom0Altitude: 190_319_879.0)

// Convert from MapCameraPosition to MKMapCamera
public extension MapCameraPosition {
    func toMKMapCamera() -> MKMapCamera {
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: zoom,
            latitude: position.latitude,
            tilt: tilt
        )
        let clampedTilt = max(0.0, min(tilt, 90.0))
        let tiltRadians = clampedTilt * .pi / 180.0
        let cosTilt = max(cos(tiltRadians), 0.05)
        let distance = altitude / cosTilt
        return MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: position.latitude,
                longitude: position.longitude
            ),
            fromDistance: distance,
            pitch: tilt,
            heading: bearing
        )
    }
}

// Convert from MKMapView to MapCameraPosition
public extension MKMapView {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition {
        let cameraAltitude = camera.altitude
        let zoom = converter.altitudeToZoomLevel(
            altitude: cameraAltitude,
            latitude: camera.centerCoordinate.latitude,
            tilt: camera.pitch
        )

        return MapCameraPosition(
            position: GeoPoint(
                latitude: camera.centerCoordinate.latitude,
                longitude: camera.centerCoordinate.longitude,
                altitude: cameraAltitude
            ),
            zoom: zoom,
            bearing: camera.heading,
            tilt: camera.pitch,
            visibleRegion: visibleRegion
        )
    }
}
