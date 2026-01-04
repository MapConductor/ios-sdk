import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibrePolylineOverlayRenderer: AbstractPolylineOverlayRenderer<[MLNPolylineFeature]> {
    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    let polylineLayer: PolylineLayer
    private let polylineManager: PolylineManager<[MLNPolylineFeature]>

    init(
        mapView: MLNMapView?,
        polylineManager: PolylineManager<[MLNPolylineFeature]>,
        polylineLayer: PolylineLayer
    ) {
        self.mapView = mapView
        self.polylineManager = polylineManager
        self.polylineLayer = polylineLayer
        super.init()
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
        polylineLayer.ensureAdded(to: style)
    }

    func unbind() {
        if let style {
            polylineLayer.remove(from: style)
        }
        style = nil
        mapView = nil
    }

    override func createPolyline(state: PolylineState) async -> [MLNPolylineFeature]? {
        createMapLibreLines(
            id: state.id,
            points: state.points,
            geodesic: state.geodesic,
            strokeColor: state.strokeColor,
            strokeWidth: state.strokeWidth,
            zIndex: (state.extra as? Int) ?? 0
        )
    }

    override func updatePolylineProperties(
        polyline: [MLNPolylineFeature],
        current: PolylineEntity<[MLNPolylineFeature]>,
        prev: PolylineEntity<[MLNPolylineFeature]>
    ) async -> [MLNPolylineFeature]? {
        createMapLibreLines(
            id: current.state.id,
            points: current.state.points,
            geodesic: current.state.geodesic,
            strokeColor: current.state.strokeColor,
            strokeWidth: current.state.strokeWidth,
            zIndex: (current.state.extra as? Int) ?? 0
        )
    }

    override func removePolyline(entity: PolylineEntity<[MLNPolylineFeature]>) async {
        // Removal is handled by redrawing all remaining polylines in onPostProcess.
    }

    override func onPostProcess() async {
        let features = polylineManager.allEntities().flatMap { $0.polyline ?? [] }
        polylineLayer.setFeatures(features)
    }
}
