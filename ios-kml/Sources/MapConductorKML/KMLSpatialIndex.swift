import Foundation

/// フィーチャーの矩形を粗い格子へ入れた索引。
///
/// タイル 1 枚ごとに全フィーチャーの矩形を見ると、数万件では描画より
/// 探す方が重くなる。格子のセルにフィーチャー番号を入れておき、
/// タイルにかかるセルだけを辿る。
///
/// android-sdk の android-kml と同名ファイルと同じ作り。
final class KMLSpatialIndex {
    /// 索引を引く方が高くつく件数では作らない。
    static let buildThreshold = 256
    static let gridSize = 64

    private let grid: [[Int]]
    private let gridSize: Int
    private let featureCount: Int

    private init(grid: [[Int]], gridSize: Int, featureCount: Int) {
        self.grid = grid
        self.gridSize = gridSize
        self.featureCount = featureCount
    }

    static func build(_ features: [RenderFeature]) -> KMLSpatialIndex {
        let size = gridSize
        var grid = Array(repeating: [Int](), count: size * size)
        for (i, feature) in features.enumerated() {
            let b = feature.bounds
            let x0 = max(0, min(size - 1, Int(b.minX * Double(size))))
            let x1 = max(0, min(size - 1, Int(b.maxX * Double(size))))
            let y0 = max(0, min(size - 1, Int(b.minY * Double(size))))
            let y1 = max(0, min(size - 1, Int(b.maxY * Double(size))))
            for cy in y0...y1 {
                for cx in x0...x1 {
                    grid[cy * size + cx].append(i)
                }
            }
        }
        return KMLSpatialIndex(grid: grid, gridSize: size, featureCount: features.count)
    }

    func query(x1: Double, y1: Double, x2: Double, y2: Double) -> [Int] {
        let cx0 = max(0, min(gridSize - 1, Int(x1 * Double(gridSize))))
        let cx1 = max(0, min(gridSize - 1, Int(x2 * Double(gridSize))))
        let cy0 = max(0, min(gridSize - 1, Int(y1 * Double(gridSize))))
        let cy1 = max(0, min(gridSize - 1, Int(y2 * Double(gridSize))))
        // [Bool] uses 1 byte per feature vs Set<Int> which needs 8+ bytes per entry,
        // preventing OOM when many features fall into the same tile.
        var seen = [Bool](repeating: false, count: featureCount)
        var result: [Int] = []
        for cy in cy0...cy1 {
            for cx in cx0...cx1 {
                for idx in grid[cy * gridSize + cx] {
                    if !seen[idx] {
                        seen[idx] = true
                        result.append(idx)
                    }
                }
            }
        }
        return result
    }
}
