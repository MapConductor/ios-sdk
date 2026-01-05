import Foundation
import MapConductorCore

final class RasterLayerPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let rasterLayerState: RasterLayerState

    init() {
        let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        let source = RasterSource.urlTemplate(
            template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            tileSize: 256
        )
        self.rasterLayerState = RasterLayerState(source: source)
    }
}
