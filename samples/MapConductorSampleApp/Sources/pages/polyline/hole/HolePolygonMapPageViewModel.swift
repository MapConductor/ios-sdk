import Foundation
import MapConductorCore
import UIKit

final class HolePolygonMapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let polygonState: PolygonState

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 43.06050568387817, longitude: 141.35374551567804),
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.polygonState = PolygonState(
            points: [
                GeoPoint(latitude: 85.0, longitude: 90.0),
                GeoPoint(latitude: 85.0, longitude: 0.1),
                GeoPoint(latitude: 85.0, longitude: -90.0),
                GeoPoint(latitude: 85.0, longitude: -179.9),
                GeoPoint(latitude: 0.0, longitude: -179.9),
                GeoPoint(latitude: -85.0, longitude: -179.9),
                GeoPoint(latitude: -85.0, longitude: -90.0),
                GeoPoint(latitude: -85.0, longitude: 0.1),
                GeoPoint(latitude: -85.0, longitude: 90.0),
                GeoPoint(latitude: -85.0, longitude: 179.9),
                GeoPoint(latitude: 0.0, longitude: 179.9),
                GeoPoint(latitude: 85.0, longitude: 179.9)
            ],
            id: "hole_polygon",
            strokeColor: .red,
            strokeWidth: 2.0,
            fillColor: UIColor(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 128.0 / 255.0, alpha: 0.8),
            geodesic: false,
            holes: [
                [
                    GeoPoint(latitude: 43.10086924222251, longitude: 141.35290903949243),
                    GeoPoint(latitude: 43.04444342582366, longitude: 141.4118953480885),
                    GeoPoint(latitude: 43.05060149394299, longitude: 141.30656265416695)
                ],
                [
                    GeoPoint(latitude: 43.06035050410283, longitude: 141.31990479539704),
                    GeoPoint(latitude: 43.038284739487004, longitude: 141.33324693662706),
                    GeoPoint(latitude: 43.049062034871525, longitude: 141.28690055130158)
                ]
            ]
        )
    }
}
