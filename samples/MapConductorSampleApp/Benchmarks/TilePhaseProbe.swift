import MapConductorCore
import UIKit
import XCTest

/// タイル 1 枚の時間が、問い合わせと描画のどちらに消えているかを測る。
///
/// android-vectortile の `MARKERTILE_PHASES` に対応する。あちらは
/// `query=102.4ms prepare=20.1ms draw=196.0ms` で描画が支配的だが、それは
/// Android の数字で、iOS のものではない。GPU 化をどこに当てるかを決める前に、
/// この板の上で測る必要がある。
///
/// core に計測を足さずに外から出す。問い合わせは `findMarkersInBounds` を同じ
/// 境界で直接呼び、残りを `renderTile` との差として見る。
final class TilePhaseProbe: XCTestCase {

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
                MarkerEntity(marker: nil,
                             state: MarkerState(position: GeoPoint(latitude: lat, longitude: lng)),
                             visible: true, isRendered: true, tiling: true)
            )
        }
        return manager
    }

    private func tileBounds(x: Int, y: Int, z: Int) -> GeoRectBounds {
        func lon(_ tx: Double) -> Double { tx / pow(2.0, Double(z)) * 360.0 - 180.0 }
        func lat(_ ty: Double) -> Double {
            let n = Double.pi - 2.0 * Double.pi * ty / pow(2.0, Double(z))
            return 180.0 / .pi * atan(0.5 * (exp(n) - exp(-n)))
        }
        return GeoRectBounds(
            southWest: GeoPoint(latitude: lat(Double(y) + 1), longitude: lon(Double(x))),
            northEast: GeoPoint(latitude: lat(Double(y)), longitude: lon(Double(x) + 1))
        )
    }

    private func ms(_ body: () -> Void) -> Double {
        let t = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
    }

    func testPhaseBreakdown() {
        MarkerTilePhaseTrace.enabled = true
        defer { MarkerTilePhaseTrace.enabled = false }

        let live = manager(144_183)
        let scale = Double(UIScreen.main.scale)
        let tileSize = 256 * max(1, Int(scale))

        for zoom in [9, 11, 12, 13] {
            let n = Double(1 << zoom)
            let latRad = 35.68 * Double.pi / 180
            let x = Int((139.75 + 180.0) / 360.0 * n)
            let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)

            let render = MarkerTileRenderer<AnyObject>(
                markerManager: live,
                tileSize: tileSize,
                cacheSizeBytes: 8 * 1024 * 1024,
                iconScaleCallback: { _, z in
                    (z > 15 ? 1.4 : (z > 13 ? 1.0 : (z > 11 ? 0.7 : 0.5))) * scale
                },
                declutterPx: 14
            )
            // 格子を温めてから測る。構築コストは別の話。
            render.clear()
            _ = render.renderTile(request: TileRequest(x: x, y: y, z: zoom))

            let bounds = tileBounds(x: x, y: y, z: zoom)
            let span = max(bounds.toSpan()?.latitude ?? 0, bounds.toSpan()?.longitude ?? 0)
            let separation = span * 14.0 / Double(tileSize)

            var queried = 0
            let queryMs = ms {
                queried = live.findMarkersInBounds(bounds, minSeparationDegrees: separation).count
            }
            render.clear()
            let totalMs = ms { _ = render.renderTile(request: TileRequest(x: x, y: y, z: zoom)) }

            print(String(
                format: "PHASES z=%d markers=%d query=%.1fms total=%.1fms rest=%.1fms queryShare=%.0f%%",
                zoom, queried, queryMs, totalMs, totalMs - queryMs, 100 * queryMs / max(totalMs, 0.001)))
        }
    }
}
