import Combine
import MapConductorCore
import SwiftUI

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
