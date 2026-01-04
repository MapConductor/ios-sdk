import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibrePolygonOverlayRenderer: AbstractPolygonOverlayRenderer<[MLNPolygonFeature]> {
    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    let polygonLayer: PolygonLayer
    private let polygonManager: PolygonManager<[MLNPolygonFeature]>

    init(
        mapView: MLNMapView?,
        polygonManager: PolygonManager<[MLNPolygonFeature]>,
        polygonLayer: PolygonLayer
    ) {
        self.mapView = mapView
        self.polygonManager = polygonManager
        self.polygonLayer = polygonLayer
        super.init()
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
        polygonLayer.ensureAdded(to: style)
    }

    func unbind() {
        if let style {
            polygonLayer.remove(from: style)
        }
        style = nil
        mapView = nil
    }

    override func createPolygon(state: PolygonState) async -> [MLNPolygonFeature]? {
        createMapLibrePolygons(
            id: state.id,
            points: state.points,
            geodesic: state.geodesic,
            fillColor: state.fillColor,
            strokeColor: state.strokeColor,
            strokeWidth: state.strokeWidth,
            zIndex: state.zIndex
        )
    }

    override func updatePolygonProperties(
        polygon: [MLNPolygonFeature],
        current: PolygonEntity<[MLNPolygonFeature]>,
        prev: PolygonEntity<[MLNPolygonFeature]>
    ) async -> [MLNPolygonFeature]? {
        createMapLibrePolygons(
            id: current.state.id,
            points: current.state.points,
            geodesic: current.state.geodesic,
            fillColor: current.state.fillColor,
            strokeColor: current.state.strokeColor,
            strokeWidth: current.state.strokeWidth,
            zIndex: current.state.zIndex
        )
    }

    override func removePolygon(entity: PolygonEntity<[MLNPolygonFeature]>) async {
        // Removal is handled by redrawing all remaining polygons in onPostProcess.
    }

    override func onPostProcess() async {
        let features = polygonManager.allEntities().flatMap { $0.polygon ?? [] }
        polygonLayer.setFeatures(features)
    }
}
