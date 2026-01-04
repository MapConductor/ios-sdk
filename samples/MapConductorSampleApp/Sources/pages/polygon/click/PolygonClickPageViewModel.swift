import Foundation
import MapConductorCore

final class PolygonClickPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published private(set) var markerState: MarkerState?
    @Published private(set) var message: String = ""

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 36.73030, longitude: -120.24512),
            zoom: 5.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func onMapClicked(_ clicked: GeoPoint) {
        message = "Outside"
        markerState = MarkerState(
            position: clicked,
            id: "clicked",
        )
    }

    func onPolygonClicked(_ event: PolygonEvent) {
        let latLng = GeoPoint.from(position: event.clicked).toUrlValue()
        message = "Inside\n\(latLng)"
        markerState = MarkerState(
            position: GeoPoint.from(position: event.clicked),
            id: "clicked", 
        )
    }
}
