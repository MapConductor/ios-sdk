import Foundation
import MapConductorCore

private struct Spot {
    let id: String
    let name: String
    let animation: MarkerAnimation
    let point: GeoPoint
}

private let exampleSpots = [
    Spot(
        id: "s1",
        name: "Bounce",
        animation: .Bounce,
        point: GeoPoint.fromLatLong(latitude: 21.3069, longitude: -157.8583)
    ),
    Spot(
        id: "s2",
        name: "Drop",
        animation: .Drop,
        point: GeoPoint.fromLatLong(latitude: 21.4513, longitude: -158.0152)
    ),
]

final class AnimationPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let allMarkers: [MarkerState]

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint.fromLatLong(
                latitude: 21.382314,
                longitude: -157.933097
            ),
            zoom: 9.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.allMarkers = exampleSpots.map { spot in
            MarkerState(
                position: spot.point,
                id: spot.id,
                extra: spot.animation,
                icon: DefaultMarkerIcon(label: spot.name),
                animation: nil
            )
        }

        // Set onClick handlers after initialization
        self.allMarkers.forEach { marker in
            marker.onClick = { [weak self] clicked in
                self?.onMarkerClick(clicked)
            }
        }
    }

    func getSpotName(markerId: String) -> String {
        guard let spot = exampleSpots.first(where: { $0.id == markerId }) else {
            fatalError("Spot not found: \(markerId)")
        }
        return spot.name
    }

    func onMarkerClick(_ clicked: MarkerState) {
        // When you want to activate the marker, set the animation for the marker.
        if let animation = clicked.extra as? MarkerAnimation {
            clicked.animate(animation)
        }
    }
}
