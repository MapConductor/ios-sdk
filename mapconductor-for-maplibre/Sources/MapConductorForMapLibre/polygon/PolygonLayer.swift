import Foundation
import MapLibre

final class PolygonLayer {
    enum Prop {
        static let fillColor = "fillColor"
        static let strokeColor = "strokeColor"
        static let strokeWidth = "strokeWidth"
        static let zIndex = "zIndex"
        static let polygonId = "polygon_id"
    }

    let sourceId: String
    let fillLayerId: String
    let lineLayerId: String

    private(set) var source: MLNShapeSource?
    private(set) var fillLayer: MLNFillStyleLayer?
    private(set) var lineLayer: MLNLineStyleLayer?

    init(sourceId: String, fillLayerId: String, lineLayerId: String) {
        self.sourceId = sourceId
        self.fillLayerId = fillLayerId
        self.lineLayerId = lineLayerId
    }

    func ensureAdded(to style: MLNStyle) {
        let existingSource = style.source(withIdentifier: sourceId) as? MLNShapeSource
        let existingFill = style.layer(withIdentifier: fillLayerId) as? MLNFillStyleLayer
        let existingLine = style.layer(withIdentifier: lineLayerId) as? MLNLineStyleLayer

        if let existingSource, let existingFill, let existingLine {
            source = existingSource
            fillLayer = existingFill
            lineLayer = existingLine
            return
        }

        let source = existingSource ?? MLNShapeSource(identifier: sourceId, features: [], options: nil)
        if existingSource == nil {
            style.addSource(source)
        }

        let fillLayer = existingFill ?? MLNFillStyleLayer(identifier: fillLayerId, source: source)
        if existingFill == nil {
            fillLayer.fillColor = NSExpression(forKeyPath: Prop.fillColor)
            if fillLayer.responds(to: Selector(("fillSortKey"))) {
                fillLayer.setValue(NSExpression(forKeyPath: Prop.zIndex), forKey: "fillSortKey")
            }
            style.addLayer(fillLayer)
        }

        let lineLayer = existingLine ?? MLNLineStyleLayer(identifier: lineLayerId, source: source)
        if existingLine == nil {
            lineLayer.lineColor = NSExpression(forKeyPath: Prop.strokeColor)
            lineLayer.lineWidth = NSExpression(forKeyPath: Prop.strokeWidth)
            lineLayer.lineJoin = NSExpression(forConstantValue: "round")
            lineLayer.lineCap = NSExpression(forConstantValue: "round")
            if lineLayer.responds(to: Selector(("lineSortKey"))) {
                lineLayer.setValue(NSExpression(forKeyPath: Prop.zIndex), forKey: "lineSortKey")
            }
            style.addLayer(lineLayer)
        }

        self.source = source
        self.fillLayer = fillLayer
        self.lineLayer = lineLayer
    }

    func setFeatures(_ features: [MLNPolygonFeature]) {
        guard let source else { return }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    func remove(from style: MLNStyle) {
        if let fillLayer {
            style.removeLayer(fillLayer)
        }
        if let lineLayer {
            style.removeLayer(lineLayer)
        }
        if let source {
            style.removeSource(source)
        }
        fillLayer = nil
        lineLayer = nil
        source = nil
    }
}
