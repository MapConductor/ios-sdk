import Foundation
import MapConductorCore
import MapLibre

@MainActor
final class MapLibreGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<MapLibreGroundImageHandle> {
    private weak var mapView: MLNMapView?
    private var style: MLNStyle?

    private let tileServer: LocalTileServer

    init(mapView: MLNMapView?) {
        self.mapView = mapView
        self.tileServer = TileServerRegistry.get()
        super.init()
    }

    func onStyleLoaded(_ style: MLNStyle) {
        self.style = style
    }

    func unbind() {
        style = nil
        mapView = nil
    }

    func createGroundImageSync(state: GroundImageState) -> MapLibreGroundImageHandle? {
        guard let style else { return nil }

        let routeId = buildSafeRouteId(state.id)
        let provider = GroundImageTileProvider(tileSize: state.tileSize)
        provider.update(state: state, opacity: 1.0)
        tileServer.register(routeId: routeId, provider: provider)

        let sourceId = "mapconductor-groundimage-source-\(routeId)"
        let layerId = "mapconductor-groundimage-layer-\(routeId)"

        removeSourceAndLayerIfExists(style: style, sourceId: sourceId, layerId: layerId)

        let tileTemplate = tileServer.urlTemplate(routeId: routeId, version: 0)
        let tileSource = makeTileSource(id: sourceId, template: tileTemplate, tileSize: state.tileSize)
        let layer = MLNRasterStyleLayer(identifier: layerId, source: tileSource)
        layer.rasterOpacity = NSExpression(forConstantValue: min(max(state.opacity, 0.0), 1.0))
        layer.isVisible = true

        style.addSource(tileSource)
        insertLayer(layer, into: style)

        return MapLibreGroundImageHandle(
            routeId: routeId,
            version: 0,
            sourceId: sourceId,
            layerId: layerId,
            tileProvider: provider,
            tileSource: tileSource,
            rasterLayer: layer
        )
    }

    func updateGroundImageSync(
        groundImage: MapLibreGroundImageHandle,
        current: GroundImageEntity<MapLibreGroundImageHandle>,
        prev: GroundImageEntity<MapLibreGroundImageHandle>
    ) -> MapLibreGroundImageHandle? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        guard let style else { return groundImage }

        if finger.opacity != prevFinger.opacity {
            groundImage.rasterLayer.rasterOpacity = NSExpression(forConstantValue: min(max(current.state.opacity, 0.0), 1.0))
        }

        let tileSizeChanged = finger.tileSize != prevFinger.tileSize
        let tileContentChanged = tileSizeChanged || finger.bounds != prevFinger.bounds || finger.image != prevFinger.image
        guard tileContentChanged else { return groundImage }

        let provider: GroundImageTileProvider
        if tileSizeChanged {
            provider = GroundImageTileProvider(tileSize: current.state.tileSize)
            tileServer.register(routeId: groundImage.routeId, provider: provider)
        } else {
            provider = groundImage.tileProvider
        }
        provider.update(state: current.state, opacity: 1.0)

        let nextVersion = groundImage.version + 1
        let tileTemplate = tileServer.urlTemplate(routeId: groundImage.routeId, version: nextVersion)

        removeSourceAndLayerIfExists(style: style, sourceId: groundImage.sourceId, layerId: groundImage.layerId)

        let tileSource = makeTileSource(id: groundImage.sourceId, template: tileTemplate, tileSize: current.state.tileSize)
        let layer = MLNRasterStyleLayer(identifier: groundImage.layerId, source: tileSource)
        layer.rasterOpacity = NSExpression(forConstantValue: min(max(current.state.opacity, 0.0), 1.0))
        layer.isVisible = true

        style.addSource(tileSource)
        insertLayer(layer, into: style)

        return MapLibreGroundImageHandle(
            routeId: groundImage.routeId,
            version: nextVersion,
            sourceId: groundImage.sourceId,
            layerId: groundImage.layerId,
            tileProvider: provider,
            tileSource: tileSource,
            rasterLayer: layer
        )
    }

    func removeGroundImageSync(entity: GroundImageEntity<MapLibreGroundImageHandle>) {
        guard let style, let handle = entity.groundImage else { return }
        removeSourceAndLayerIfExists(style: style, sourceId: handle.sourceId, layerId: handle.layerId)
        tileServer.unregister(routeId: handle.routeId)
    }

    override func createGroundImage(state: GroundImageState) async -> MapLibreGroundImageHandle? {
        createGroundImageSync(state: state)
    }

    override func updateGroundImageProperties(
        groundImage: MapLibreGroundImageHandle,
        current: GroundImageEntity<MapLibreGroundImageHandle>,
        prev: GroundImageEntity<MapLibreGroundImageHandle>
    ) async -> MapLibreGroundImageHandle? {
        updateGroundImageSync(groundImage: groundImage, current: current, prev: prev)
    }

    override func removeGroundImage(entity: GroundImageEntity<MapLibreGroundImageHandle>) async {
        removeGroundImageSync(entity: entity)
    }

    private func makeTileSource(id: String, template: String, tileSize: Int) -> MLNRasterTileSource {
        let options: [MLNTileSourceOption: Any] = [
            .tileSize: NSNumber(value: tileSize),
            .minimumZoomLevel: NSNumber(value: 0),
            .maximumZoomLevel: NSNumber(value: 22)
        ]
        return MLNRasterTileSource(identifier: id, tileURLTemplates: [template], options: options)
    }

    private func removeSourceAndLayerIfExists(style: MLNStyle, sourceId: String, layerId: String) {
        if let layer = style.layer(withIdentifier: layerId) {
            style.removeLayer(layer)
        }
        if let source = style.source(withIdentifier: sourceId) {
            style.removeSource(source)
        }
    }

    private func insertLayer(_ layer: MLNRasterStyleLayer, into style: MLNStyle) {
        if let below = findBelowLayer(style: style) {
            style.insertLayer(layer, below: below)
        } else {
            style.addLayer(layer)
        }
    }

    private func findBelowLayer(style: MLNStyle) -> MLNStyleLayer? {
        let prefixes = [
            "mapconductor-polylines-layer-",
            "mapconductor-polygons-fill-",
            "mapconductor-polygons-line-",
            "mapconductor-circles-layer-",
            "mapconductor-cluster-layer-",
            "mapconductor-raster-layer-",
            "mapconductor-markers-layer-"
        ]
        for prefix in prefixes {
            if let layer = style.layers.first(where: { $0.identifier.hasPrefix(prefix) }) {
                return layer
            }
        }
        return nil
    }

    private func buildSafeRouteId(_ id: String) -> String {
        var out = "groundimage-"
        out.reserveCapacity(out.count + id.count)
        for ch in id {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else {
                out.append("_")
            }
        }
        return out
    }
}
