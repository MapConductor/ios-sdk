import Foundation
import MapLibre

final class MarkerLayer {
    let sourceId: String
    let layerId: String

    private(set) var source: MLNShapeSource?
    private(set) var layer: MLNSymbolStyleLayer?

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }

    func ensureAdded(to style: MLNStyle) {
        let existingSource = style.source(withIdentifier: sourceId) as? MLNShapeSource
        let existingLayer = style.layer(withIdentifier: layerId) as? MLNSymbolStyleLayer

        if let existingSource, let existingLayer {
            source = existingSource
            layer = existingLayer
            return
        }

        let source = existingSource ?? MLNShapeSource(identifier: sourceId, features: [], options: nil)
        if existingSource == nil {
            style.addSource(source)
        }

        let layer = existingLayer ?? MLNSymbolStyleLayer(identifier: layerId, source: source)
        if existingLayer == nil {
            layer.iconImageName = NSExpression(forKeyPath: MapLibreMarkerOverlayRenderer.Prop.iconId)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconAnchor = NSExpression(forConstantValue: "top-left")
            layer.iconTranslationAnchor = NSExpression(forConstantValue: "map")
            layer.iconOffset = NSExpression(forKeyPath: MapLibreMarkerOverlayRenderer.Prop.iconAnchor)
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

