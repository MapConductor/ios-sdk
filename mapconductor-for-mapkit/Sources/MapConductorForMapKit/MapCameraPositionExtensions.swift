import Foundation
import MapKit
import MapConductorCore

private let converter = MapKitZoomAltitudeConverter(zoom0Altitude: 171_319_879.0)
private let mapConductorTileSizePoints: Double = 256.0
private let minCosLat: Double = 0.01

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
        let zoom = googleLikeZoomLevel()
            ?? converter.altitudeToZoomLevel(
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

private extension MKMapView {
    func googleLikeZoomLevel() -> Double? {
        guard !bounds.isEmpty else { return nil }
        let widthPoints = Double(bounds.width)
        guard widthPoints > 0 else { return nil }

        // Use map points to avoid great-circle distance (CLLocation.distance), so this matches Web Mercator scaling.
        let midY = bounds.midY
        let leftCoordinate = convert(CGPoint(x: 0, y: midY), toCoordinateFrom: self)
        let rightCoordinate = convert(CGPoint(x: bounds.maxX, y: midY), toCoordinateFrom: self)

        let leftMapPoint = MKMapPoint(leftCoordinate)
        let rightMapPoint = MKMapPoint(rightCoordinate)
        let deltaMapPoints = hypot(rightMapPoint.x - leftMapPoint.x, rightMapPoint.y - leftMapPoint.y)
        guard deltaMapPoints > 0 else { return nil }

        let centerLat = max(-85.0, min(camera.centerCoordinate.latitude, 85.0))
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(centerLat)
        guard pointsPerMeter > 0 else { return nil }
        let metersSpan = deltaMapPoints / pointsPerMeter
        guard metersSpan > 0 else { return nil }

        let metersPerPoint = metersSpan / widthPoints

        let latitudeRadians = centerLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let zoom = log2((Earth.circumferenceMeters * cosLat) / (mapConductorTileSizePoints * metersPerPoint))
        guard zoom.isFinite else { return nil }
        return max(0.0, min(zoom, 22.0))
    }
}
