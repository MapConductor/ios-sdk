import XCTest

/// 現行の平坦キーと、geomodel 方式の階層キーを同じデータで比べる。
///
/// cordova-plugin-googlemaps の `geomodel.js` は、各段で 4x4 に割った位置を
/// 16 進 1 文字にする:
///
///     _subdiv_char(x, y) = (y & 2) << 2 | (x & 2) << 1 | (y & 1) << 1 | (x & 1)
///
/// これは緯度経度のビットを交互に並べたもの（Morton 順）を 4 ビットずつ切った
/// ものと同じで、**粗いセルが細かいセルの前置になる**。
///
/// 現行の `MarkerGridIndex` は `(lat << 20) | lon` の行優先なので前置にならず、
/// 粗さを変えるには段ごとに配列を作り直すしかない。実機で 1 段あたり 340ms
/// かかっていた。そのコストが階層キーで本当に消えるのかを測る。
final class GeocellKeyProbe: XCTestCase {

    private static let count = 144_183
    private static let depth: Int64 = 19  // 軸あたり 19 ビット。+ 位置 24 ビットで 62。

    private struct Lcg {
        private var seed: UInt64 = 12345
        mutating func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
    }

    private func positions() -> [(Double, Double)] {
        var lcg = Lcg()
        return (0..<Self.count).map { _ in (35.5 + lcg.next() * 0.4, 139.5 + lcg.next() * 0.5) }
    }

    /// 現行方式: セル幅ごとに (lat, lon) を行優先で詰め、段ごとに並べ替える。
    private func flatKeys(_ points: [(Double, Double)], cellDegrees: Double) -> [Int64] {
        var keys = [Int64](); keys.reserveCapacity(points.count)
        for (at, p) in points.enumerated() {
            let lat = Int64((p.0 / cellDegrees).rounded(.down))
            let lon = Int64((p.1 / cellDegrees).rounded(.down))
            keys.append(((((lat + 262_144) << 20) | (lon + 524_288)) << 24) | Int64(at))
        }
        keys.sort()
        return keys
    }

    /// geomodel 方式: 最も細かい段で 1 本だけ作る。粗い段は上位ビットの前置。
    private func mortonKeysUnsorted(_ points: [(Double, Double)]) -> [Int64] {
        var keys = [Int64](); keys.reserveCapacity(points.count)
        let side = Double(Int64(1) << Self.depth)
        for (at, p) in points.enumerated() {
            let latIdx = Int64(((p.0 + 90.0) / 180.0 * side).rounded(.down))
            let lonIdx = Int64(((p.1 + 180.0) / 360.0 * side).rounded(.down))
            var morton: Int64 = 0
            for b in stride(from: Self.depth - 1, through: 0, by: -1) {
                morton = (morton << 2) | (((latIdx >> b) & 1) << 1) | ((lonIdx >> b) & 1)
            }
            keys.append((morton << 24) | Int64(at))
        }
        return keys
    }

    private func mortonKeys(_ points: [(Double, Double)]) -> [Int64] {
        var keys = [Int64](); keys.reserveCapacity(points.count)
        let side = Double(Int64(1) << Self.depth)
        for (at, p) in points.enumerated() {
            let latIdx = Int64(((p.0 + 90.0) / 180.0 * side).rounded(.down))
            let lonIdx = Int64(((p.1 + 180.0) / 360.0 * side).rounded(.down))
            var morton: Int64 = 0
            for b in stride(from: Self.depth - 1, through: 0, by: -1) {
                morton = (morton << 2) | (((latIdx >> b) & 1) << 1) | ((lonIdx >> b) & 1)
            }
            keys.append((morton << 24) | Int64(at))
        }
        keys.sort()
        return keys
    }

    private func lowerBound(_ a: [Int64], _ target: Int64) -> Int {
        var low = 0, high = a.count
        while low < high { let mid = (low + high) >> 1; if a[mid] < target { low = mid + 1 } else { high = mid } }
        return low
    }

    private func ms(_ body: () -> Void) -> Double {
        let t = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000
    }

    func testBuildCostAcrossLevels() {
        let points = positions()

        // ズーム 11/12/13 が要求する分離距離に対応する段。
        let wanted: [(zoom: Int, separation: Double)] = [(11, 0.0032), (12, 0.0016), (13, 0.0008)]

        print("GEOCELL points=\(points.count)")

        // 現行方式: 段ごとに 1 本ずつ作る。
        var flatTotal = 0.0
        for w in wanted {
            let t = ms { _ = self.flatKeys(points, cellDegrees: w.separation) }
            flatTotal += t
            print(String(format: "GEOCELL flat   z=%d cell=%.5f build=%.0fms", w.zoom, w.separation, t))
        }
        print(String(format: "GEOCELL flat   合計 build=%.0fms（段ごとに払う）", flatTotal))

        // geomodel 方式: 1 本だけ。
        // 鍵の計算と並べ替えを分けて測る。GPU に出せるのは前者だけ -- 後者は
        // 要素間に依存があり、素直な並列化ができない。
        var raw: [Int64] = []
        let keyCost = ms { raw = self.mortonKeysUnsorted(points) }
        var morton: [Int64] = []
        let sortCost = ms { morton = raw.sorted() }
        print(String(format: "GEOCELL morton 鍵計算=%.0fms 並べ替え=%.0fms 合計=%.0fms",
                     keyCost, sortCost, keyCost + sortCost))
        print(String(format: "GEOCELL morton 鍵計算の占める割合=%.0f%%",
                     100 * keyCost / (keyCost + sortCost)))

        // その 1 本から各段の粗さで問い合わせられることを確認する。
        for w in wanted {
            // 段 k のセル幅（経度）= 360 / 2^k。要求された分離以下になる最大の k。
            var level = Self.depth
            while level > 1 && 360.0 / Double(Int64(1) << level) < w.separation { level -= 1 }
            let shift = (Self.depth - level) * 2
            // 東京中心の 1 タイル相当の箱に入るセルを、前置の範囲として数える。
            let t = ms {
                var cells = 0
                var at = 0
                var previous: Int64 = -1
                while at < morton.count {
                    let coarse = (morton[at] >> 24) >> shift
                    if coarse != previous { cells += 1; previous = coarse }
                    // 同じ粗いセルの終端まで一気に飛ぶ（前置なので連続している）
                    let limit = ((coarse + 1) << shift) << 24
                    at = self.lowerBound(morton, limit)
                }
                print(String(format: "GEOCELL morton z=%d level=%d cellDeg=%.5f cells=%d",
                             w.zoom, level, 360.0 / Double(Int64(1) << level), cells))
            }
            print(String(format: "GEOCELL morton z=%d 走査=%.1fms（build 追加なし）", w.zoom, t))
        }
        XCTAssertGreaterThan(morton.count, 0)
    }

    /// 比較ソート・基数ソート・ハッシュ表を同じ鍵で比べる。
    ///
    /// 「ソートを外してハッシュにすれば 194ms が消えるのでは」に対する実測。
    /// 平坦な格子ならハッシュで足りるが、geomodel の前置範囲は順序に依存する。
    /// そして順序が要るとしても、鍵は上限のある整数なので比較ソートである必要は
    /// ない -- 基数ソートは O(n) で、接頭辞和は GPU に出せる。
    func testSortAlternatives() {
        let points = positions()
        var raw: [Int64] = []
        let keyCost = ms { raw = self.mortonKeysUnsorted(points) }

        let comparison = ms { _ = raw.sorted() }

        var radixResult: [Int64] = []
        let radix = ms { radixResult = Self.radixSorted(raw) }

        // ハッシュ表: セル -> そのセルのマーカー位置
        var table: [Int64: [Int32]] = [:]
        let hashing = ms {
            table = [:]
            table.reserveCapacity(raw.count / 4)
            for key in raw {
                table[key >> 24, default: []].append(Int32(key & 0xFFFFFF))
            }
        }

        print(String(format: "SORTALT 鍵計算=%.0fms", keyCost))
        print(String(format: "SORTALT 比較ソート=%.0fms  基数ソート=%.0fms  ハッシュ表=%.0fms",
                     comparison, radix, hashing))
        print(String(format: "SORTALT 基数/比較=%.2fx  セル数=%d", radix / comparison, table.count))
        XCTAssertEqual(radixResult, raw.sorted(), "基数ソートの結果が比較ソートと違う")
    }

    /// 下位 8 ビットずつ、8 周。鍵は 62 ビットなので符号の扱いは要らない。
    private static func radixSorted(_ input: [Int64]) -> [Int64] {
        var source = input
        var destination = [Int64](repeating: 0, count: input.count)
        for pass in 0..<8 {
            let shift = Int64(pass * 8)
            var counts = [Int](repeating: 0, count: 256)
            for value in source { counts[Int((value >> shift) & 0xFF)] += 1 }
            // 接頭辞和。GPU ではここが scan になる。
            var total = 0
            for bucket in 0..<256 {
                let count = counts[bucket]
                counts[bucket] = total
                total += count
            }
            for value in source {
                let bucket = Int((value >> shift) & 0xFF)
                destination[counts[bucket]] = value
                counts[bucket] += 1
            }
            swap(&source, &destination)
        }
        return source
    }

    /// geomodel 本来の文字列キーと、同じ階層を整数で表したものを比べる。
    ///
    /// `GEOCELL_ALPHABET = '0123456789abcdef'` は 4 ビットを 1 文字に写している
    /// だけなので、文字列の前置と整数の上位ビットは同じものを指す。違うのは
    /// 1 件あたりの費用で、このリポジトリは以前 String id を 1 件ごとに持って
    /// 144,183 本で OOM を起こしている。
    func testStringKeyVersusIntegerKey() {
        let points = positions()
        let alphabet = Array("0123456789abcdef")
        let resolution = 9   // 4 ビット x 9 = 36 ビット。整数版の 38 ビットとほぼ同じ粒度。

        // --- geomodel 本来の形: 文字列を組み立てる ---
        var cells: [String] = []
        let stringBuild = ms {
            cells = points.map { point in
                var south = -90.0, north = 90.0, west = -180.0, east = 180.0
                var cell = ""
                cell.reserveCapacity(resolution)
                for _ in 0..<resolution {
                    let latSpan = (north - south) / 4.0
                    let lonSpan = (east - west) / 4.0
                    let x = min(Int((point.1 - west) / lonSpan), 3)
                    let y = min(Int((point.0 - south) / latSpan), 3)
                    // _subdiv_char と同じ: (y&2)<<2 | (x&2)<<1 | (y&1)<<1 | (x&1)
                    let index = ((y & 2) << 2) | ((x & 2) << 1) | ((y & 1) << 1) | (x & 1)
                    cell.append(alphabet[index])
                    south += latSpan * Double(y); north = south + latSpan
                    west += lonSpan * Double(x); east = west + lonSpan
                }
                return cell
            }
        }

        // 文字列キーのハッシュ表
        var stringTable: [String: [Int32]] = [:]
        let stringHash = ms {
            stringTable = [:]
            stringTable.reserveCapacity(points.count / 4)
            for (at, cell) in cells.enumerated() {
                stringTable[cell, default: []].append(Int32(at))
            }
        }

        // 粗い段への切り出し = 前置を取る
        var coarse: [String: [Int32]] = [:]
        let stringCoarse = ms {
            coarse = [:]
            for (cell, list) in stringTable {
                coarse[String(cell.prefix(6)), default: []].append(contentsOf: list)
            }
        }

        // --- 整数版: 同じ階層 ---
        var raw: [Int64] = []
        let intBuild = ms { raw = self.mortonKeysUnsorted(points) }
        var intTable: [Int64: [Int32]] = [:]
        let intHash = ms {
            intTable = [:]
            intTable.reserveCapacity(points.count / 4)
            for key in raw { intTable[key >> 24, default: []].append(Int32(key & 0xFFFFFF)) }
        }
        var intCoarse: [Int64: [Int32]] = [:]
        let intCoarseCost = ms {
            intCoarse = [:]
            for (key, list) in intTable { intCoarse[key >> 12, default: []].append(contentsOf: list) }
        }

        print(String(format: "STRKEY 文字列: 組み立て=%.0fms ハッシュ=%.0fms 粗い段=%.0fms 合計=%.0fms cells=%d",
                     stringBuild, stringHash, stringCoarse, stringBuild + stringHash + stringCoarse, stringTable.count))
        print(String(format: "STRKEY 整数  : 組み立て=%.0fms ハッシュ=%.0fms 粗い段=%.0fms 合計=%.0fms cells=%d",
                     intBuild, intHash, intCoarseCost, intBuild + intHash + intCoarseCost, intTable.count))
        print(String(format: "STRKEY 粗い段のセル数 文字列=%d 整数=%d", coarse.count, intCoarse.count))
        XCTAssertGreaterThan(stringTable.count, 0)
    }
}
