import MapConductorCore
import MapKit

@MainActor
final class MapConductorPointAnnotation: MKPointAnnotation {
    let markerId: String
    let markerState: MarkerState
    let initialBitmapIcon: BitmapIcon

    init(markerState: MarkerState, bitmapIcon: BitmapIcon) {
        self.markerId = markerState.id
        self.markerState = markerState
        self.initialBitmapIcon = bitmapIcon
        super.init()
        self.title = markerState.id
        self.coordinate = CLLocationCoordinate2D(
            latitude: markerState.position.latitude,
            longitude: markerState.position.longitude
        )
    }
}

