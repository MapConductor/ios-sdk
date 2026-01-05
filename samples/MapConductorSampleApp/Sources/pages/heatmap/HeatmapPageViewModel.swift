import Foundation
import MapConductorCore
import MapConductorHeatmap

final class HeatmapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let heatmap: HeatmapOverlay
    let heatmapPoints: [HeatmapPoint]

    init() {
        let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.heatmap = HeatmapOverlay()
        self.heatmapPoints = tokyoPostOffices.map { office in
            HeatmapPoint(position: office.position, weight: 1.0)
        }
    }

    func onCameraMove(_ camera: MapCameraPosition) {
        heatmap.onCameraChanged(camera)
    }
}
