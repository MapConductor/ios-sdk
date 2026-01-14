import Foundation
import MapConductorCore
import MapConductorHeatmap

final class HeatmapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let heatmap: HeatmapOverlayState
    let heatmapPoints: [HeatmapPointState]

    init() {
        let center = GeoPoint(latitude: 35.681236, longitude: 139.767125)
        self.initCameraPosition = MapCameraPosition(
            position: center,
            zoom: 11.0,
            bearing: 0.0,
            tilt: 0.0,
            paddings: nil
        )

        self.heatmap = HeatmapOverlayState(tileSize: 512)
        self.heatmapPoints = tokyoPostOffices.enumerated().map { index, office in
            HeatmapPointState(position: office.position, weight: 1.0, id: "postoffice-\(index)")
        }
    }

    func setUseCameraZoomForTiles(isGoogleMaps: Bool) {
        heatmap.useCameraZoomForTiles = true
    }

    func onCameraMove(provider: MapProvider, camera: MapCameraPosition) {
        heatmap.onCameraChanged(camera)
    }
}
