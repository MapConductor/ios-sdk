import Foundation
import MapConductorCore
import MapConductorHeatmap

@MainActor
final class HeatmapPageViewModel: ObservableObject {
    let initCameraPosition: MapCameraPosition
    let heatmap: HeatmapOverlayState
    @Published var heatmapPoints: [HeatmapPointState] = []

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

        Task { [weak self] in
            guard let self else { return }
            let offices = await PostOfficeDataLoader().loadAllPostOffices()
            self.heatmapPoints = offices.enumerated().map { index, office in
                HeatmapPointState(position: office.position, weight: 1.0, id: "postoffice-\(index)")
            }
        }
    }

    func onCameraMove(provider: MapProvider, camera: MapCameraPosition) {
        heatmap.onCameraChanged(camera)
    }
}
