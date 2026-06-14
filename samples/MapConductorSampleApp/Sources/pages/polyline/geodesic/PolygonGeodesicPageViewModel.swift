import Foundation
import MapConductorCore
import UIKit

final class PolygonGeodesicPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition

    @Published private(set) var markerState: MarkerState?

    init() {
        self.initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: 30.0, longitude: 0.0),
            zoom: 1.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )
    }

    func onPolygonClicked(_ event: PolygonEvent) {
        let color = event.state.fillColor.withAlphaComponent(1.0)
        markerState = MarkerState(
            position: GeoPoint.from(position: event.clicked),
            id: "clicked",
            icon: DefaultMarkerIcon(fillColor: color)
        )
    }
}
