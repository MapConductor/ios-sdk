import CoreGraphics
import Foundation
import MapConductorCore
import UIKit

/// KML をタイルへ描くタイルプロバイダ。
///
/// このファイルが持つのは**元データの保持とタイル要求の段取り**だけで、
/// 実際の計算は責務ごとのファイルにある:
///
/// | ファイル                          | 担当                                      |
/// |-----------------------------------|-------------------------------------------|
/// | ``KMLWorld``                  | 緯度経度→世界座標、範囲                   |
/// | ``KMLRenderFeatureBuilder``   | スタイル解決と描画用フィーチャーの組み立て|
/// | ``KMLSpatialIndex``           | タイルにかかるフィーチャーの絞り込み      |
/// | ``KMLTilePainter``            | CGContext への描画                        |
/// | ``KMLHitTester``              | クリック位置の当たり判定                  |
///
/// android-sdk の android-kml も同じ責務分けのファイル構成にしてある。
public final class KMLTileRenderer: TileProvider {

    // MARK: - Public

    public let tileSize: Int

    public struct LayerStyle {
        public let strokeColor: UIColor
        public let fillColor: UIColor
        public let strokeWidth: CGFloat
        public let pointRadius: CGFloat

        public init(
            strokeColor: UIColor = KMLDefaults.defaultStrokeColor,
            fillColor: UIColor = KMLDefaults.defaultFillColor,
            strokeWidth: CGFloat = KMLDefaults.defaultStrokeWidth,
            pointRadius: CGFloat = KMLDefaults.defaultPointRadius
        ) {
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            self.strokeWidth = strokeWidth
            self.pointRadius = pointRadius
        }
    }

    public struct KMLHitTestResult {
        public let feature: KMLFeature
        public let position: GeoPoint
    }

    // MARK: - State

    /// 描画中に元データが差し替わっても矛盾しないよう、1 回ぶんをまとめて固めたもの。
    private struct TileState {
        let features: [RenderFeature]
        let index: KMLSpatialIndex?
    }

    private let stateLock = NSLock()
    private var currentState = TileState(features: [], index: nil)

    private let cacheLock = NSLock()
    private let cache = NSCache<NSString, NSData>()
    private var cacheEpoch: Int64 = 0

    private static let maxCacheCostBytes = 8 * 1024 * 1024

    // MARK: - Init

    public init(tileSize: Int = KMLDefaults.defaultTileSize) {
        self.tileSize = tileSize
        cache.totalCostLimit = Self.maxCacheCostBytes
    }

    // MARK: - Update

    public func update(
        features: [KMLFeature],
        layerStyle: LayerStyle,
        styleProvider: any KMLStyleProvider = DefaultKMLStyleProvider.shared
    ) {
        let rendered = features.filter { $0.visible }.map {
            KMLRenderFeatureBuilder.build($0, layerStyle: layerStyle, styleProvider: styleProvider)
        }
        let index = rendered.count >= KMLSpatialIndex.buildThreshold
            ? KMLSpatialIndex.build(rendered)
            : nil
        stateLock.lock()
        currentState = TileState(features: rendered, index: index)
        stateLock.unlock()
        cacheLock.lock()
        cacheEpoch += 1
        cache.removeAllObjects()
        cacheLock.unlock()
    }

    // MARK: - TileProvider

    public func renderTile(request: TileRequest) -> Data? {
        let epoch: Int64
        cacheLock.lock()
        epoch = cacheEpoch
        cacheLock.unlock()

        let pixelRatio = max(1, min(request.pixelRatio, 3))
        let normalizedRequest = TileRequest(x: request.x, y: request.y, z: request.z, pixelRatio: pixelRatio)
        let key = "\(epoch):\(pixelRatio)x:\(request.z)/\(request.x)/\(request.y)" as NSString
        cacheLock.lock()
        let cached = cache.object(forKey: key)
        cacheLock.unlock()
        if let cached { return cached as Data }

        stateLock.lock()
        let state = currentState
        stateLock.unlock()

        let result = renderTileInternal(request: normalizedRequest, state: state)

        cacheLock.lock()
        if cacheEpoch == epoch {
            cache.setObject((result ?? Data()) as NSData, forKey: key, cost: result?.count ?? 1)
        }
        cacheLock.unlock()

        return result
    }

    // MARK: - Hit testing

    /// Returns the topmost feature at the given geographic coordinates, or nil.
    ///
    /// Pass `lineTolSq` and `pointTolSq` (squared world-coordinate tolerances) to override the
    /// default hit tolerances. Prefer using ``KMLLayerState/processClick(geoPoint:pixelTolerance:zoom:)``
    /// which converts a pixel tolerance automatically.
    ///
    /// 走査は**後ろから**行う。あとに描いたものが上に見えるので、上にあるものを先に返す。
    public func hitTest(
        longitude: Double,
        latitude: Double,
        lineTolSq: Double? = nil,
        pointTolSq: Double? = nil
    ) -> KMLHitTestResult? {
        let wx = KMLWorld.lonToWorld(longitude)
        let wy = KMLWorld.latToWorld(latitude)

        stateLock.lock()
        let state = currentState
        stateLock.unlock()

        let lineTol = lineTolSq.map { $0.squareRoot() } ?? KMLDefaults.hitLineTolerance
        let pointTol = pointTolSq.map { $0.squareRoot() } ?? KMLDefaults.hitPointTolerance
        let tol = max(lineTol, pointTol)
        let candidates = state.index?.query(x1: wx - tol, y1: wy - tol, x2: wx + tol, y2: wy + tol)
            ?? Array(state.features.indices)

        for idx in candidates.reversed() {
            let feature = state.features[idx]
            guard feature.bounds.intersects(wx - tol, wy - tol, wx + tol, wy + tol) else { continue }
            if let hit = KMLHitTester.hitTestGeometry(
                wx: wx, wy: wy, geometry: feature.worldGeometry, lineTolSq: lineTolSq, pointTolSq: pointTolSq
            ) {
                return KMLHitTestResult(
                    feature: feature.source,
                    position: GeoPoint.fromLongLat(
                        longitude: KMLWorld.worldToLon(hit.wx),
                        latitude: KMLWorld.worldToLat(hit.wy)
                    )
                )
            }
        }
        return nil
    }

    public func hitTestFeature(
        longitude: Double,
        latitude: Double,
        lineTolSq: Double? = nil,
        pointTolSq: Double? = nil
    ) -> KMLFeature? {
        hitTest(longitude: longitude, latitude: latitude, lineTolSq: lineTolSq, pointTolSq: pointTolSq)?.feature
    }

    // MARK: - Internal rendering

    /// - Returns: タイルの PNG。描くものが無いときは nil。
    private func renderTileInternal(request: TileRequest, state: TileState) -> Data? {
        guard !state.features.isEmpty else { return nil }

        let z = request.z
        let worldTileCount = 1 << z
        // x は世界を巻き回す（日付変更線をまたいだ要求が来る）。y は範囲外なら描かない。
        let x = ((request.x % worldTileCount) + worldTileCount) % worldTileCount
        let y = request.y
        guard y >= 0 && y < worldTileCount else { return nil }

        let tileMinX = Double(x) / Double(worldTileCount)
        let tileMaxX = Double(x + 1) / Double(worldTileCount)
        let tileMinY = Double(y) / Double(worldTileCount)
        let tileMaxY = Double(y + 1) / Double(worldTileCount)

        let candidates = state.index?.query(x1: tileMinX, y1: tileMinY, x2: tileMaxX, y2: tileMaxY)
            ?? Array(state.features.indices)

        let worldSize = Double(tileSize) * Double(worldTileCount)
        let originX = Double(x) * Double(tileSize)
        let originY = Double(y) * Double(tileSize)

        func toPixelX(_ wx: Double) -> CGFloat { CGFloat(wx * worldSize - originX) }
        func toPixelY(_ wy: Double) -> CGFloat { CGFloat(wy * worldSize - originY) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(request.pixelRatio)
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: tileSize, height: tileSize),
            format: format
        )
        var hasContent = false

        let image = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.clear(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))

            for idx in candidates {
                let feature = state.features[idx]
                guard feature.bounds.intersects(tileMinX, tileMinY, tileMaxX, tileMaxY) else { continue }
                if KMLTilePainter.drawFeature(cgCtx, feature: feature, toPixelX: toPixelX, toPixelY: toPixelY) {
                    hasContent = true
                }
            }
        }

        guard hasContent else { return nil }
        return image.pngData()
    }
}
