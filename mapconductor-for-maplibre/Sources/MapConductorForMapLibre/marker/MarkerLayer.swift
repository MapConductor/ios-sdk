import Foundation
import MapLibre
import UIKit

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
            layer.iconImageName = NSExpression(forKeyPath: MapLibreMarkerRenderer.Prop.iconId)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            layer.iconAnchor = NSExpression(forConstantValue: "top-left")
            layer.iconOpacity = NSExpression(
                format: "TERNARY(%K == 1, 0, 1)",
                MapLibreMarkerRenderer.Prop.isHidden
            )
            // Keep marker icons screen-aligned (like GoogleMaps) to avoid resampling blur when the map rotates/pitches.
            layer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
            layer.iconPitchAlignment = NSExpression(forConstantValue: "viewport")
            // MapLibre renders style images as if they were @1x. We compensate by:
            // - registering images with `UIImage.scale = 1` (points == pixels)
            // - scaling down the symbol by the screen scale to match other providers.
            layer.iconScale = NSExpression(forConstantValue: 1.0 / UIScreen.main.scale)
            layer.iconTranslationAnchor = NSExpression(forConstantValue: "map")
            layer.iconOffset = NSExpression(forKeyPath: MapLibreMarkerRenderer.Prop.iconAnchor)
            style.addLayer(layer)
        }

        self.source = source
        self.layer = layer
    }

    func setFeatures(_ features: [MLNPointFeature]) {
        guard let source else { return }
        // MapLibre can crash if we mutate a source that is no longer part of the current style
        // (e.g. during/after a style reload). Fail safe by ensuring we still have a layer too.
        guard layer != nil else { return }
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
