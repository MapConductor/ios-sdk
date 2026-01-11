import MapConductorCore
import MapLibre

final class MapLibreRasterLayer {
    let source: MLNRasterTileSource
    let layer: MLNRasterStyleLayer

    init(source: MLNRasterTileSource, layer: MLNRasterStyleLayer) {
        self.source = source
        self.layer = layer
    }
}

@MainActor
final class MapLibreRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<MapLibreRasterLayer> {
    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    init(mapView: MLNMapView?) {
        self.mapView = mapView
        super.init()
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
    }

    func unbind() {
        style = nil
        mapView = nil
    }

    // Synchronous versions of layer operations to avoid async/await issues
    func createLayerSync(state: RasterLayerState) -> MapLibreRasterLayer? {
        guard let style else { return nil }

        let sourceId = "mapconductor-raster-source-\(state.id)"
        let layerId = "mapconductor-raster-layer-\(state.id)"

        // Remove existing layer and source if they already exist
        if let existingLayer = style.layer(withIdentifier: layerId) {
            style.removeLayer(existingLayer)
        }
        if let existingSource = style.source(withIdentifier: sourceId) {
            style.removeSource(existingSource)
        }

        let source = makeTileSource(id: sourceId, source: state.source)
        let layer = MLNRasterStyleLayer(identifier: layerId, source: source)
        layer.rasterOpacity = NSExpression(forConstantValue: state.opacity)
        layer.isVisible = state.visible

        style.addSource(source)
        if let topLayer = style.layers.last {
            style.insertLayer(layer, below: topLayer)
        } else {
            style.addLayer(layer)
        }

        return MapLibreRasterLayer(source: source, layer: layer)
    }

    func updateLayerSync(
        layer: MapLibreRasterLayer,
        current: RasterLayerEntity<MapLibreRasterLayer>,
        prev: RasterLayerEntity<MapLibreRasterLayer>
    ) -> MapLibreRasterLayer? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        guard let style else { return layer }

        if finger.source != prevFinger.source {
            // Recreate layer with new source
            if style.layer(withIdentifier: layer.layer.identifier) != nil {
                style.removeLayer(layer.layer)
            }
            if style.source(withIdentifier: layer.source.identifier) != nil {
                style.removeSource(layer.source)
            }
            return createLayerSync(state: current.state)
        }

        if finger.opacity != prevFinger.opacity {
            layer.layer.rasterOpacity = NSExpression(forConstantValue: current.state.opacity)
        }

        if finger.visible != prevFinger.visible {
            layer.layer.isVisible = current.state.visible
        }

        return layer
    }

    func removeLayerSync(entity: RasterLayerEntity<MapLibreRasterLayer>) {
        guard let style, let layer = entity.layer else { return }

        if style.layer(withIdentifier: layer.layer.identifier) != nil {
            style.removeLayer(layer.layer)
        }
        if style.source(withIdentifier: layer.source.identifier) != nil {
            style.removeSource(layer.source)
        }
    }

    override func createLayer(state: RasterLayerState) async -> MapLibreRasterLayer? {
        // Delegate to synchronous version to avoid async/await issues
        return createLayerSync(state: state)
    }

    override func updateLayerProperties(
        layer: MapLibreRasterLayer,
        current: RasterLayerEntity<MapLibreRasterLayer>,
        prev: RasterLayerEntity<MapLibreRasterLayer>
    ) async -> MapLibreRasterLayer? {
        // Delegate to synchronous version to avoid async/await issues
        return updateLayerSync(layer: layer, current: current, prev: prev)
    }

    override func removeLayer(entity: RasterLayerEntity<MapLibreRasterLayer>) async {
        // Delegate to synchronous version to avoid async/await issues
        removeLayerSync(entity: entity)
    }

    private func makeTileSource(id: String, source: RasterSource) -> MLNRasterTileSource {
        switch source {
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, _):
            var options: [MLNTileSourceOption: Any] = [
                .tileSize: NSNumber(value: tileSize)
            ]
            if let minZoom {
                options[.minimumZoomLevel] = NSNumber(value: minZoom)
            }
            if let maxZoom {
                options[.maximumZoomLevel] = NSNumber(value: maxZoom)
            }
            return MLNRasterTileSource(identifier: id, tileURLTemplates: [template], options: options)
        case .tileJson:
            fatalError("RasterSource.tileJson is not implemented for MapLibre yet.")
        case .arcGisService:
            fatalError("RasterSource.arcGisService is not implemented for MapLibre yet.")
        }
    }
}
