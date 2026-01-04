import Foundation
import MapConductorCore
import UIKit

final class FlyToPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let markers: [MarkerState]

    @Published var geodesic: Bool = false

    private let honoluluLocation = GeoPoint.fromLatLong(latitude: 21.3099, longitude: -157.8581)
    private let tokyoLocation = GeoPoint.fromLatLong(latitude: 35.6762, longitude: 139.6503)
    private let londonLocation = GeoPoint.fromLatLong(latitude: 51.5074, longitude: -0.1278)
    private let newYorkLocation = GeoPoint.fromLatLong(latitude: 40.7128, longitude: -74.0060)
    private let sydneyLocation = GeoPoint.fromLatLong(latitude: -33.9506, longitude: 151.1815)

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: tokyoLocation,
            zoom: 0.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.markers = [
            MarkerState(
                position: honoluluLocation,
                id: "honolulu_marker",
                icon: DefaultMarkerIcon(label: "HNL")
            ),
            MarkerState(
                position: tokyoLocation,
                id: "tokyo_marker",
                icon: DefaultMarkerIcon(label: "TYO")
            ),
            MarkerState(
                position: londonLocation,
                id: "london_marker",
                icon: DefaultMarkerIcon(label: "LON")
            ),
            MarkerState(
                position: newYorkLocation,
                id: "newyork_marker",
                icon: DefaultMarkerIcon(label: "NYC")
            ),
            MarkerState(
                position: sydneyLocation,
                id: "sydney_marker",
                icon: DefaultMarkerIcon(label: "SYD")
            )
        ]
    }

    var polylines: [PolylineState] {
        let alpha: CGFloat = 0.7
        return [
            PolylineState(
                points: [honoluluLocation, newYorkLocation],
                id: "honolulu_to_newyork",
                strokeColor: UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [honoluluLocation, sydneyLocation],
                id: "honolulu_to_sydney",
                strokeColor: UIColor(red: 0.7, green: 0.0, blue: 0.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [tokyoLocation, londonLocation],
                id: "tokyo_to_london",
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [tokyoLocation, newYorkLocation],
                id: "tokyo_to_newyork",
                strokeColor: UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [tokyoLocation, honoluluLocation],
                id: "tokyo_to_honolulu",
                strokeColor: UIColor(red: 1.0, green: 0.35, blue: 0.12, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [londonLocation, newYorkLocation],
                id: "london_to_newyork",
                strokeColor: UIColor(red: 0.75, green: 0.0, blue: 0.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            ),
            PolylineState(
                points: [londonLocation, sydneyLocation],
                id: "london_to_sydney",
                strokeColor: UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: alpha),
                strokeWidth: 3.0,
                geodesic: geodesic
            )
        ]
    }

    func flyToHonolulu(state: MapViewStateProtocol) {
        flyToLocation(state: state, location: honoluluLocation, zoom: 10.0)
    }

    func flyToTokyo(state: MapViewStateProtocol) {
        flyToLocation(state: state, location: tokyoLocation, zoom: 10.0)
    }

    func flyToLondon(state: MapViewStateProtocol) {
        flyToLocation(state: state, location: londonLocation, zoom: 10.0)
    }

    func flyToNewYork(state: MapViewStateProtocol) {
        flyToLocation(state: state, location: newYorkLocation, zoom: 10.0)
    }

    func flyToSydney(state: MapViewStateProtocol) {
        flyToLocation(state: state, location: sydneyLocation, zoom: 10.0)
    }

    private func flyToLocation(state: MapViewStateProtocol, location: GeoPoint, zoom: Double) {
        let newCameraPosition = MapCameraPosition(
            position: location,
            zoom: zoom,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
        state.moveCameraTo(cameraPosition: newCameraPosition, durationMillis: 1500)
    }
}
