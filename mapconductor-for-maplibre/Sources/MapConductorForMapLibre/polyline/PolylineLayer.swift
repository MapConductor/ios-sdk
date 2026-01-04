import Foundation
import MapLibre

final class PolylineLayer {
    enum Prop {
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let zIndex = "zIndex"
        static let polylineId = "polyline_id"
    }

    let sourceId: String
    let layerId: String

    private(set) var source: MLNShapeSource?
    private(set) var layer: MLNLineStyleLayer?

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    func ensureAdded(to style: MLNStyle) {
        let existingSource = style.source(withIdentifier: sourceId) as? MLNShapeSource
        let existingLayer = style.layer(withIdentifier: layerId) as? MLNLineStyleLayer

        if let existingSource, let existingLayer {
            source = existingSource
            layer = existingLayer
            return
        }

        let source = existingSource ?? MLNShapeSource(identifier: sourceId, features: [], options: nil)
        if existingSource == nil {
            style.addSource(source)
        }

        let layer = existingLayer ?? MLNLineStyleLayer(identifier: layerId, source: source)
        if existingLayer == nil {
            layer.lineJoin = NSExpression(forConstantValue: "round")
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineColor = NSExpression(forKeyPath: Prop.strokeColor)
            layer.lineWidth = NSExpression(forKeyPath: Prop.strokeWidth)
            if layer.responds(to: Selector(("lineSortKey"))) {
                layer.setValue(NSExpression(forKeyPath: Prop.zIndex), forKey: "lineSortKey")
            }
            style.addLayer(layer)
        }

        self.source = source
        self.layer = layer
    }

    func setFeatures(_ features: [MLNPolylineFeature]) {
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
