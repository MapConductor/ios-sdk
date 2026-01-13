import Foundation
import MapLibre
import MapConductorCore

internal let mapLibreCameraZoomAdjustValue = 1.0

// Convert from MapCameraPosition to MLNMapCamera with adjusted zoom
public extension MapCameraPosition {
    func toMLNMapCamera() -> MLNMapCamera {
        let camera = MLNMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: position.latitude,
                longitude: position.longitude
            ),
            altitude: 0,
            pitch: tilt,
            heading: bearing
        )
        return camera
    }

    /// Returns the adjusted zoom level for MapLibre
    func adjustedZoomForMapLibre() -> Double {
        max(zoom - mapLibreCameraZoomAdjustValue, 0.0)
    }
}

// Convert from MLNMapView to MapCameraPosition
public extension MLNMapView {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition {
        MapCameraPosition(
            position: GeoPoint(
                latitude: centerCoordinate.latitude,
                longitude: centerCoordinate.longitude,
                altitude: 0
            ),
            zoom: zoomLevel + mapLibreCameraZoomAdjustValue,
            bearing: camera.heading,
            tilt: camera.pitch,
            visibleRegion: visibleRegion
        )
    }
}
