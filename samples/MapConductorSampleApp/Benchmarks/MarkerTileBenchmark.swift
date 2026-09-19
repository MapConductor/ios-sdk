import MapConductorCore
import XCTest

/// マーカータイル 1 枚の実測コストを**実機で**測る。
///
/// ios-sdk-core にも同じ内容の `MarkerTileCostTests` があるが、あちらは SPM の
/// テストターゲットなので実機では走らない:
///
///     Cannot test target "MapConductorCoreTests" on "iPad":
///     Tool-hosted testing is unavailable on device destinations.
///
/// ホストアプリが要る。それがこのターゲットの存在理由で、ここはサンプルアプリに
/// ホストされている。シミュレータは M シリーズの Mac で動くので、実機より速い
/// 方向に嘘をつく -- 「Android より遅い」を追うのにシミュレータの数字は使えない。
///
/// 条件は android-vectortile の `MarkerTileCostTest` と揃えてある。同じ LCG
/// シード、同じ緯度経度の分布、同じマーカー数、同じタイルサイズ、同じズーム。
final class MarkerTileBenchmark: XCTestCase {

    private let tileSize = 512

    /// android 側と同じ線形合同法。定数まで同じなので同じ座標が同じ順で出る。
    private struct Lcg {
        private var seed: UInt64 = 12345
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
    }

    private func manager(_ count: Int) -> MarkerManager<AnyObject> {
        let manager = MarkerManager<AnyObject>.defaultManager(minMarkerCount: 1)
        var lcg = Lcg()
        for _ in 0..<count {
            let lat = 35.5 + lcg.next() * 0.4
            let lng = 139.5 + lcg.next() * 0.5
            manager.registerEntity(
                MarkerEntity(
                    marker: nil,
                    state: MarkerState(position: GeoPoint(latitude: lat, longitude: lng)),
                    visible: true,
                    isRendered: true,
                    tiling: true
                )
            )
        }
        return manager
    }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    private func tileXY(zoom: Int) -> (Int, Int) {
        let n = Double(1 << zoom)
        let lat = 35.68 * .pi / 180
        return (
            Int((139.75 + 180.0) / 360.0 * n),
            Int((1.0 - log(tan(lat) + 1.0 / cos(lat)) / .pi) / 2.0 * n)
        )
    }

    /// 街路樹サンプルと同じ 144,183 本。android の `StreetTreeCostTest` と同じズーム。
    func testStreetTreeScaleOnDevice() {
        let live = manager(144_183)
        for declutter in [0, 14] {
            for zoom in [9, 11, 12, 14] {
                let (x, y) = tileXY(zoom: zoom)
                let request = TileRequest(x: x, y: y, z: zoom)
                let render = MarkerTileRenderer(
                    markerManager: live,
                    tileSize: tileSize,
                    cacheSizeBytes: 8 * 1024 * 1024,
                    declutterPx: declutter
                )
                var samples: [Double] = []
                var bytes = 0
                for _ in 0..<3 {
                    render.clear()
                    let started = DispatchTime.now().uptimeNanoseconds
                    let data = render.renderTile(request: request)
                    samples.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                    bytes = data?.count ?? 0
                }
                print(
                    String(
                        format: "DEVICE TREES declutter=%d z=%d render=%.0fms png=%dKB",
                        declutter, zoom, median(samples), bytes / 1024
                    )
                )
            }
        }
    }
}
