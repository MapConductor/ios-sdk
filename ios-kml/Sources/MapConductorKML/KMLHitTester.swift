import CoreGraphics
import Foundation
import MapConductorCore

/// 当たった位置と、そこまでの距離の 2 乗。近い方を選ぶために距離を持つ。
struct GeometryHit {
    let wx: Double
    let wy: Double
    let distanceSq: Double
}

/// クリック位置に最も近いフィーチャーを探す部分。
///
/// 点・線・面で判定が違う:
/// - 点と線は**許容距離**で拾う。1px の線をピクセル単位で当てるのは無理なので、
///   世界座標での余裕を持たせる。
/// - 面は内外判定（交差数の偶奇）。穴の中は当たりにしない。
///
/// android-sdk の android-kml と同名ファイルと同じ判定。
enum KMLHitTester {
    static func hitTestGeometry(
        wx: Double,
        wy: Double,
        geometry: WorldGeometry,
        lineTolSq: Double? = nil,
        pointTolSq: Double? = nil
    ) -> GeometryHit? {
        let effectivePointTolSq = pointTolSq ?? KMLDefaults.hitPointSq
        switch geometry {
        case .point(let gx, let gy):
            let d = KMLWorld.distanceSq(wx, wy, gx, gy)
            return d <= effectivePointTolSq ? GeometryHit(wx: gx, wy: gy, distanceSq: d) : nil
        case .points(let pts):
            var best: GeometryHit?
            for point in pts {
                let d = KMLWorld.distanceSq(wx, wy, point.wx, point.wy)
                if d <= effectivePointTolSq, best == nil || d < best!.distanceSq {
                    best = GeometryHit(wx: point.wx, wy: point.wy, distanceSq: d)
                }
            }
            return best
        case .line(let rings):
            return hitTestRings(wx: wx, wy: wy, rings: rings, lineTolSq: lineTolSq)
        case .polygon(let rings):
            // lineTolSq が指定されたときは「輪郭に近いか」を見る（線として扱う）。
            if lineTolSq != nil {
                return hitTestRings(wx: wx, wy: wy, rings: rings, lineTolSq: lineTolSq)
            }
            guard let exterior = rings.first, pointInRing(wx: wx, wy: wy, ring: exterior) else { return nil }
            return !rings.dropFirst().contains { pointInRing(wx: wx, wy: wy, ring: $0) }
                ? GeometryHit(wx: wx, wy: wy, distanceSq: 0)
                : nil
        case .collection(let parts):
            var best: GeometryHit?
            for part in parts {
                if let hit = hitTestGeometry(
                    wx: wx, wy: wy, geometry: part, lineTolSq: lineTolSq, pointTolSq: pointTolSq
                ), best == nil || hit.distanceSq < best!.distanceSq {
                    best = hit
                }
            }
            return best
        case .empty:
            return nil
        }
    }

    private static func hitTestRings(
        wx: Double,
        wy: Double,
        rings: [[WorldPoint]],
        lineTolSq: Double? = nil
    ) -> GeometryHit? {
        var best: GeometryHit?
        for ring in rings {
            if let hit = hitTestLine(wx: wx, wy: wy, ring: ring, lineTolSq: lineTolSq),
               best == nil || hit.distanceSq < best!.distanceSq {
                best = hit
            }
        }
        return best
    }

    private static func hitTestLine(
        wx: Double,
        wy: Double,
        ring: [WorldPoint],
        lineTolSq: Double? = nil
    ) -> GeometryHit? {
        let effectiveLineTolSq = lineTolSq ?? KMLDefaults.hitLineSq
        var best: GeometryHit?
        let testPoint = CGPoint(x: wx, y: wy)
        for (a, b) in zip(ring, ring.dropFirst()) {
            let closest = closestPointOnSegment(
                startPoint: CGPoint(x: a.wx, y: a.wy),
                endPoint: CGPoint(x: b.wx, y: b.wy),
                testPoint: testPoint
            )
            let cx = Double(closest.x)
            let cy = Double(closest.y)
            let dSq = KMLWorld.distanceSq(wx, wy, cx, cy)
            if dSq <= effectiveLineTolSq, best == nil || dSq < best!.distanceSq {
                best = GeometryHit(wx: cx, wy: cy, distanceSq: dSq)
            }
        }
        return best
    }

    /// 交差数の偶奇による内外判定（ray casting）。
    private static func pointInRing(wx: Double, wy: Double, ring: [WorldPoint]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].wx, yi = ring[i].wy
            let xj = ring[j].wx, yj = ring[j].wy
            if ((yi > wy) != (yj > wy)) && (wx < (xj - xi) * (wy - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        return inside
    }
}
