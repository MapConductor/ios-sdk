import Combine
import MapConductorCore
import SwiftUI

struct CameraLocationInfo {
    let name: String
    let bounds: GeoRectBounds
    let center: GeoPoint
    let zoom: Double
}

@MainActor
class CameraSyncTestViewModel: ObservableObject {
    @Published var leftProvider: MapProvider = .googleMaps
    @Published var rightProvider: MapProvider = .mapKit

    let initCameraPosition = MapCameraPosition(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671, altitude: 0), // Tokyo
        zoom: 12.0,
        bearing: 0.0,
        tilt: 0.0
    )

    // Define locations with their bounds
    let locations: [CameraLocationInfo] = [
        CameraLocationInfo(
            name: "French Southern and Antarctic Lands",
            bounds: GeoRectBounds(
                southWest: GeoPoint(latitude: -49.5, longitude: 50.0, altitude: 0),
                northEast: GeoPoint(latitude: -37.5, longitude: 77.0, altitude: 0)
            ),
            center: GeoPoint(latitude: -43.5, longitude: 63.5, altitude: 0),
            zoom: 4.0
        ),
        CameraLocationInfo(
            name: "Finland",
            bounds: GeoRectBounds(
                southWest: GeoPoint(latitude: 59.8, longitude: 19.1, altitude: 0),
                northEast: GeoPoint(latitude: 70.1, longitude: 31.6, altitude: 0)
            ),
            center: GeoPoint(latitude: 64.95, longitude: 25.35, altitude: 0),
            zoom: 5.0
        ),
        CameraLocationInfo(
            name: "Iceland",
            bounds: GeoRectBounds(
                southWest: GeoPoint(latitude: 63.3, longitude: -24.5, altitude: 0),
                northEast: GeoPoint(latitude: 66.6, longitude: -13.5, altitude: 0)
            ),
            center: GeoPoint(latitude: 64.95, longitude: -19.0, altitude: 0),
            zoom: 6.0
        ),
        CameraLocationInfo(
            name: "Kiribati",
            bounds: GeoRectBounds(
                southWest: GeoPoint(latitude: -11.5, longitude: -174.5, altitude: 0),
                northEast: GeoPoint(latitude: 5.0, longitude: -147.0, altitude: 0)
            ),
            center: GeoPoint(latitude: -3.25, longitude: -160.75, altitude: 0),
            zoom: 4.5
        )
    ]

    // Generate reference rectangles for zoom calibration (100km x 100km approximately 1 degree)
    func getReferenceRectangles() -> [PolygonState] {
        var rectangles: [PolygonState] = []

        for location in locations {
            // Create a small rectangle near each location center for zoom reference
            let lat = location.center.latitude
            let lng = location.center.longitude
            let size = 1.0 // approximately 100km at equator

            let points = [
                GeoPoint(latitude: lat - size/2, longitude: lng - size/2, altitude: 0),
                GeoPoint(latitude: lat - size/2, longitude: lng + size/2, altitude: 0),
                GeoPoint(latitude: lat + size/2, longitude: lng + size/2, altitude: 0),
                GeoPoint(latitude: lat + size/2, longitude: lng - size/2, altitude: 0),
                GeoPoint(latitude: lat - size/2, longitude: lng - size/2, altitude: 0)
            ]

            rectangles.append(PolygonState(
                points: points,
                strokeColor: .systemBlue,
                strokeWidth: 2.0,
                fillColor: .systemBlue.withAlphaComponent(0.1),
                geodesic: false,
                zIndex: 1
            ))
        }

        return rectangles
    }

    func onLeftCameraChange(_ position: MapCameraPosition, rightState: any MapViewStateProtocol) {
        // Sync camera from left map to right map
        rightState.moveCameraTo(cameraPosition: position, durationMillis: 0)
    }

    func getProviderName(_ provider: MapProvider) -> String {
        switch provider {
        case .googleMaps:
            return "Google Maps"
        case .mapLibre:
            return "MapLibre"
        case .mapKit:
            return "MapKit"
        }
    }
}
