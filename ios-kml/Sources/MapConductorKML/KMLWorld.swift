import Foundation

/// 世界座標（0..1 の正規化 Web メルカトル）の 1 点。
struct WorldPoint {
    let wx: Double
    let wy: Double
}

struct WorldBounds {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    func intersects(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Bool {
        minX <= x2 && maxX >= x1 && minY <= y2 && maxY >= y1
    }
}

/// 世界座標へ落としたあとのジオメトリ。
///
/// 緯度経度のままではなく先に世界座標へ移しておくのは、タイルを描くたびに
/// 投影を計算し直さないため。数万点のデータでは投影が支配的になる。
indirect enum WorldGeometry {
    case point(wx: Double, wy: Double)
    case points([WorldPoint])
    case line([[WorldPoint]])
    case polygon([[WorldPoint]])
    case collection([WorldGeometry])
    case empty
}

/// 緯度経度と世界座標の相互変換、ジオメトリの世界座標化、範囲の計算。
///
/// すべて副作用のない計算で、描画にもキャッシュにも触らない。
///
/// android-sdk の android-kml の `KMLWorld.kt` と同じ式。
/// 片方だけ直すと両者の描画結果や当たり判定がずれるので、変えるときは両方直すこと。
enum KMLWorld {
    private static let maxAbsSinLat = 0.9999

    static func lonToWorld(_ lon: Double) -> Double { lon / 360.0 + 0.5 }

    static func worldToLon(_ wx: Double) -> Double { (wx - 0.5) * 360.0 }

    static func latToWorld(_ lat: Double) -> Double {
        let siny = sin(lat * .pi / 180.0)
        let clipped = max(-maxAbsSinLat, min(maxAbsSinLat, siny))
        return 0.5 - log((1.0 + clipped) / (1.0 - clipped)) / (4.0 * .pi)
    }

    static func worldToLat(_ wy: Double) -> Double {
        atan(sinh(.pi * (1.0 - 2.0 * wy))) * 180.0 / .pi
    }

    static func distanceSq(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = ax - bx, dy = ay - by
        return dx * dx + dy * dy
    }

    static func toWorldGeometry(_ geometry: KMLGeometry) -> WorldGeometry {
        switch geometry {
        case .point(let lon, let lat):
            return .point(wx: lonToWorld(lon), wy: latToWorld(lat))
        case .multiPoint(let pts):
            return .points(pts.map { WorldPoint(wx: lonToWorld($0.longitude), wy: latToWorld($0.latitude)) })
        case .lineString(let coords):
            return .line([coords.map { WorldPoint(wx: lonToWorld($0.longitude), wy: latToWorld($0.latitude)) }])
        case .multiLineString(let lines):
            return .line(lines.map { line in
                line.map { WorldPoint(wx: lonToWorld($0.longitude), wy: latToWorld($0.latitude)) }
            })
        case .polygon(let rings):
            return .polygon(rings.map { ring in
                ring.map { WorldPoint(wx: lonToWorld($0.longitude), wy: latToWorld($0.latitude)) }
            })
        case .multiPolygon(let polygons):
            return .collection(polygons.map { poly in
                .polygon(poly.map { ring in
                    ring.map { WorldPoint(wx: lonToWorld($0.longitude), wy: latToWorld($0.latitude)) }
                })
            })
        case .geometryCollection(let geometries):
            return .collection(geometries.map { toWorldGeometry($0) })
        case .empty:
            return .empty
        }
    }

    static func computeBounds(_ geometry: WorldGeometry) -> WorldBounds {
        switch geometry {
        case .point(let wx, let wy):
            return WorldBounds(minX: wx, maxX: wx, minY: wy, maxY: wy)
        case .points(let pts):
            return boundsOfPoints(pts)
        case .line(let rings):
            return boundsOfRings(rings)
        case .polygon(let rings):
            return boundsOfRings(rings)
        case .collection(let parts):
            let sub = parts.map { computeBounds($0) }
            return WorldBounds(
                minX: sub.map { $0.minX }.min() ?? 0,
                maxX: sub.map { $0.maxX }.max() ?? 1,
                minY: sub.map { $0.minY }.min() ?? 0,
                maxY: sub.map { $0.maxY }.max() ?? 1
            )
        case .empty:
            return WorldBounds(minX: 0, maxX: 1, minY: 0, maxY: 1)
        }
    }

    private static func boundsOfPoints(_ pts: [WorldPoint]) -> WorldBounds {
        guard !pts.isEmpty else { return WorldBounds(minX: 0, maxX: 1, minY: 0, maxY: 1) }
        return WorldBounds(
            minX: pts.map { $0.wx }.min()!,
            maxX: pts.map { $0.wx }.max()!,
            minY: pts.map { $0.wy }.min()!,
            maxY: pts.map { $0.wy }.max()!
        )
    }

    private static func boundsOfRings(_ rings: [[WorldPoint]]) -> WorldBounds {
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for ring in rings {
            for pt in ring {
                if pt.wx < minX { minX = pt.wx }
                if pt.wx > maxX { maxX = pt.wx }
                if pt.wy < minY { minY = pt.wy }
                if pt.wy > maxY { maxY = pt.wy }
            }
        }
        guard minX <= maxX else { return WorldBounds(minX: 0, maxX: 1, minY: 0, maxY: 1) }
        return WorldBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }
}
