import Foundation
import MapConductorCore
import MapLibre

final class MapLibreGroundImageHandle {
    let routeId: String
    let version: Int64
    let sourceId: String
    let layerId: String
    let tileProvider: GroundImageTileProvider
    let tileSource: MLNRasterTileSource
    let rasterLayer: MLNRasterStyleLayer

    init(
        routeId: String,
        version: Int64,
        sourceId: String,
        layerId: String,
        tileProvider: GroundImageTileProvider,
        tileSource: MLNRasterTileSource,
        rasterLayer: MLNRasterStyleLayer
    ) {
        self.routeId = routeId
        self.version = version
        self.sourceId = sourceId
        self.layerId = layerId
        self.tileProvider = tileProvider
        self.tileSource = tileSource
        self.rasterLayer = rasterLayer
    }

    func copy(
        version: Int64? = nil,
        tileProvider: GroundImageTileProvider? = nil,
        tileSource: MLNRasterTileSource? = nil,
        rasterLayer: MLNRasterStyleLayer? = nil
    ) -> MapLibreGroundImageHandle {
        MapLibreGroundImageHandle(
            routeId: routeId,
            version: version ?? self.version,
            sourceId: sourceId,
            layerId: layerId,
            tileProvider: tileProvider ?? self.tileProvider,
            tileSource: tileSource ?? self.tileSource,
            rasterLayer: rasterLayer ?? self.rasterLayer
        )
    }
}

