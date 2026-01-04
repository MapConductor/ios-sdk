import Foundation
import MapLibre

final class CircleLayer {
    enum Prop {
        static let radiusPixels = "radiusPixels"
        static let fillColor = "fillColor"
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let circleId = "circle_id"
    }

    let sourceId: String
    let layerId: String

    private(set) var source: MLNShapeSource?
    private(set) var layer: MLNCircleStyleLayer?

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    func ensureAdded(to style: MLNStyle) {
        let existingSource = style.source(withIdentifier: sourceId) as? MLNShapeSource
        let existingLayer = style.layer(withIdentifier: layerId) as? MLNCircleStyleLayer

        if let existingSource, let existingLayer {
            source = existingSource
            layer = existingLayer
            return
        }

        let source = existingSource ?? MLNShapeSource(identifier: sourceId, features: [], options: nil)
        if existingSource == nil {
            style.addSource(source)
        }

        let layer = existingLayer ?? MLNCircleStyleLayer(identifier: layerId, source: source)
        if existingLayer == nil {
            layer.circleRadius = NSExpression(forKeyPath: Prop.radiusPixels)
            layer.circleColor = NSExpression(forKeyPath: Prop.fillColor)
            layer.circleStrokeColor = NSExpression(forKeyPath: Prop.strokeColor)
            layer.circleStrokeWidth = NSExpression(forKeyPath: Prop.strokeWidth)
            style.addLayer(layer)
        }

        self.source = source
        self.layer = layer
    }

    func setFeatures(_ features: [MLNPointFeature]) {
        guard let source else { return }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    func remove(from style: MLNStyle) {
        if let layer {
            style.removeLayer(layer)
        }
        if let source {
            style.removeSource(source)
        }
        self.layer = nil
        self.source = nil
    }
}
