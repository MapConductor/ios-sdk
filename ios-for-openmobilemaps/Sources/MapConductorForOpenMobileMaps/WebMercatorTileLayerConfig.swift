import Foundation
import MapCore
import MapConductorCore

/// XYZ / TMS のラスタータイル 1 組ぶんの設定。
///
/// ## SDK 同梱の web メルカトル設定を使わない理由
///
/// 同梱の設定はズームレベルの縮尺が SDK 独自の基準（レベル 0 で 1:500'000'000）で
/// 刻まれている。これは MapConductor の統一ズームの基準
/// （``OpenMobileMapsZoomAltitudeConverter/scaleAtZoom0`` = 1:986'097'222）と約 2 倍ずれるので、
/// そのまま使うと**統一ズーム Z のときに 1 段低いレベルのタイルが選ばれ、常にぼやける**。
/// 自前の設定にして、レベル L の縮尺を統一ズーム L と厳密に一致させる。
///
/// ## 端末密度で補正してはいけない
///
/// `tileSize` は**画像のピクセル数ではなく dp**（ポイント）である（`RasterLayerSource.urlTemplate`
/// の意味論。MapLibre の `tileSize` も Google のタイル定義も同じ）。したがってレベルの選択は
/// ポイントだけで決まり、端末密度は関係しない。
///
/// android で一度ここに density を掛けていて、**マーカータイルが 1 段深いレベルで選ばれ、
/// PostOffice ページのアイコンが巨大かつぼやける**という形で出た。密度を掛けると
/// 高密度端末だけ挙動が変わるので、他プロバイダと並べても気づきにくい。
final class WebMercatorTileLayerConfig: NSObject, MCTiled2dMapLayerConfig {
    private static let worldWidthMeters = 40_075_016.685_578_49
    private static let halfWorld = worldWidthMeters / 2.0

    private let layerName: String
    private let urlTemplate: String
    private let tileSize: Int
    private let minZoomLevel: Int
    private let maxZoomLevel: Int
    private let scheme: TileScheme
    private let numDrawPreviousLayers: Int32
    private let maskTile: Bool

    /// - Parameters:
    ///   - urlTemplate: `{z}` `{x}` `{y}` を含む URL。
    ///   - tileSize: タイル 1 枚の一辺（**ポイント**）。OSM 系は 256、@2x 系は 512。
    ///   - scheme: `.TMS` なら y を反転する。
    init(
        layerName: String,
        urlTemplate: String,
        tileSize: Int,
        minZoomLevel: Int = 0,
        maxZoomLevel: Int = 22,
        scheme: TileScheme = .XYZ,
        numDrawPreviousLayers: Int32 = 2,
        maskTile: Bool = false
    ) {
        self.layerName = layerName
        self.urlTemplate = urlTemplate
        self.tileSize = tileSize
        self.minZoomLevel = minZoomLevel
        self.maxZoomLevel = maxZoomLevel
        self.scheme = scheme
        self.numDrawPreviousLayers = numDrawPreviousLayers
        self.maskTile = maskTile
        super.init()
    }

    func getCoordinateSystemIdentifier() -> Int32 { MCCoordinateSystemIdentifiers.epsg3857() }

    func getLayerName() -> String { layerName }

    func getTileUrl(_ x: Int32, y: Int32, t _: Int32, zoom: Int32) -> String {
        let resolvedY = scheme == .TMS ? (1 << zoom) - 1 - y : y
        return urlTemplate
            .replacingOccurrences(of: "{z}", with: String(zoom))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(resolvedY))
    }

    func getZoomLevelInfos() -> [MCTiled2dMapZoomLevelInfo] {
        (minZoomLevel ... maxZoomLevel).map { level in
            let tilesPerAxis = Int32(1 << level)
            return MCTiled2dMapZoomLevelInfo(
                zoom: zoomScaleForLevel(level: level, tileSize: tileSize),
                tileWidthLayerSystemUnits: Float(Self.worldWidthMeters / Double(tilesPerAxis)),
                numTilesX: tilesPerAxis,
                numTilesY: tilesPerAxis,
                numTilesT: 1,
                zoomLevelIdentifier: Int32(level),
                bounds: Self.webMercatorBounds()
            )
        }
    }

    func getVirtualZoomLevelInfos() -> [MCTiled2dMapZoomLevelInfo] { [] }

    func getZoomInfo() -> MCTiled2dMapZoomInfo {
        MCTiled2dMapZoomInfo(
            zoomLevelScaleFactor: 1.0,
            numDrawPreviousLayers: numDrawPreviousLayers,
            numDrawPreviousOrLaterTLayers: 0,
            adaptScaleToScreen: false,
            maskTile: maskTile,
            underzoom: true,
            overzoom: true
        )
    }

    func getVectorSettings() -> MCTiled2dMapVectorSettings? { nil }

    func getBounds() -> MCRectCoord? { Self.webMercatorBounds() }

    private static func webMercatorBounds() -> MCRectCoord {
        MCRectCoord(
            topLeft: MCCoord(
                systemIdentifier: MCCoordinateSystemIdentifiers.epsg3857(),
                x: -halfWorld, y: halfWorld, z: 0.0
            ),
            bottomRight: MCCoord(
                systemIdentifier: MCCoordinateSystemIdentifiers.epsg3857(),
                x: halfWorld, y: -halfWorld, z: 0.0
            )
        )
    }
}

/// 統一ズームが基準にしているタイルの一辺（Google 準拠の 256pt）。
private let unifiedTileSize = 256

/// タイルレベル `level` を選ばせたい縮尺。
///
/// 256pt タイルなら統一ズーム `level` の縮尺そのもの（＝ Google と同じレベルが選ばれる）。
/// 512pt タイルは 1 枚で 2 枚ぶんを覆うので 1 段浅いレベルでよい。
///
/// **端末密度を掛けないこと。** `tileSize` は画像のピクセル数ではなくポイントなので、
/// レベルの選択に密度は関係しない。
///
/// SDK に触らない純粋な計算にしてあるのは、ユニットテストで検証できるようにするため
/// （`MCTiled2dMapZoomLevelInfo` の生成は Metal と C++ の初期化を通る）。
func zoomScaleForLevel(level: Int, tileSize: Int) -> Double {
    OpenMobileMapsZoomAltitudeConverter.scaleAtZoom0
        * Double(unifiedTileSize) / Double(tileSize) / pow(2.0, Double(level))
}
