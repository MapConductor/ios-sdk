import MapConductorCore
import MapLibre
import UIKit

@MainActor
final class MapLibreCircleOverlayRenderer: AbstractCircleOverlayRenderer<MLNPointFeature> {
    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    let circleLayer: CircleLayer
    private let circleManager: CircleManager<MLNPointFeature>

    init(
        mapView: MLNMapView?,
        circleManager: CircleManager<MLNPointFeature>,
        circleLayer: CircleLayer
    ) {
        self.mapView = mapView
        self.circleManager = circleManager
        self.circleLayer = circleLayer
        super.init()
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
        circleLayer.ensureAdded(to: style)
    }

    func unbind() {
        if let style {
            circleLayer.remove(from: style)
        }
        style = nil
        mapView = nil
    }

    override func createCircle(state: CircleState) async -> MLNPointFeature? {
        makeFeature(for: state)
    }

    override func updateCircleProperties(
        circle: MLNPointFeature,
        current: CircleEntity<MLNPointFeature>,
        prev: CircleEntity<MLNPointFeature>
    ) async -> MLNPointFeature? {
        makeFeature(for: current.state)
    }

    override func removeCircle(entity: CircleEntity<MLNPointFeature>) async {
        // Removal is handled by redrawing all remaining circles in onPostProcess.
    }

    override func onPostProcess() async {
        let features = circleManager.allEntities().compactMap { entity -> MLNPointFeature? in
            let updated = makeFeature(for: entity.state)
            entity.circle = updated
            return updated
        }
        circleLayer.setFeatures(features)
    }

    private func makeFeature(for state: CircleState) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: state.center.latitude, longitude: state.center.longitude)
        feature.identifier = "circle-\(state.id)" as NSString

        let zoom = (mapView?.zoomLevel ?? 0.0) + mapLibreCameraZoomAdjustValue
        let metersPerPixel = calculateMetersPerPixel(latitude: state.center.latitude, zoom: zoom)
        let radiusPixels = metersPerPixel > 0 ? state.radiusMeters / metersPerPixel : 0.0

        feature.attributes = [
            CircleLayer.Prop.radiusPixels: radiusPixels,
            CircleLayer.Prop.fillColor: state.fillColor,
            CircleLayer.Prop.strokeColor: state.strokeColor,
            CircleLayer.Prop.strokeWidth: state.strokeWidth,
            CircleLayer.Prop.circleId: state.id
        ]
        return feature
    }
}
