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

    override func createLayer(state: RasterLayerState) async -> MapLibreRasterLayer? {
        guard let style else { return nil }
        let source = makeTileSource(id: "mapconductor-raster-source-\(state.id)", source: state.source)
        let layer = MLNRasterStyleLayer(identifier: "mapconductor-raster-layer-\(state.id)", source: source)
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

    override func updateLayerProperties(
        layer: MapLibreRasterLayer,
        current: RasterLayerEntity<MapLibreRasterLayer>,
        prev: RasterLayerEntity<MapLibreRasterLayer>
    ) async -> MapLibreRasterLayer? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        guard let style else { return layer }

        if finger.source != prevFinger.source {
            style.removeLayer(layer.layer)
            style.removeSource(layer.source)
            return await createLayer(state: current.state)
        }

        if finger.opacity != prevFinger.opacity {
            layer.layer.rasterOpacity = NSExpression(forConstantValue: current.state.opacity)
        }

        if finger.visible != prevFinger.visible {
            layer.layer.isVisible = current.state.visible
        }

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<MapLibreRasterLayer>) async {
        guard let style, let layer = entity.layer else { return }
        style.removeLayer(layer.layer)
        style.removeSource(layer.source)
    }

    private func makeTileSource(id: String, source: RasterSource) -> MLNRasterTileSource {
        switch source {
        case let .urlTemplate(template, _, minZoom, maxZoom, _, _):
            var options: [MLNTileSourceOption: Any] = [
                // MapLibre tile source is more stable with 256px tiles.
                .tileSize: NSNumber(value: 256)
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
