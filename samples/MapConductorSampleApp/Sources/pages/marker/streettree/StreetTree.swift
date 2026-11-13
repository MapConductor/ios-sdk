import CoreText
import Foundation
import MapConductorCore
import UIKit

/// Tokyo's street trees: 144,183 of them, from the metropolitan government's
/// open data.
///
/// A harder shape than the post office set. There are six times as many, they
/// sit inside one metropolitan area rather than spread over a country, and each
/// species draws its own colour — so the renderer cannot collapse two trees of
/// different species that land on the same pixel.
///
/// Species with fewer than a hundred trees are folded into one bucket. The
/// distribution has a long tail: a hundred species cover 96% of the trees, and
/// the remaining three hundred would be indistinguishable colours nobody could
/// read off a legend. The bucket is still the fifth largest group, so it is not
/// a rounding error being hidden.
struct StreetTree {
    let position: GeoPoint
    let species: String
    let speciesIndex: Int
    /// Height in metres, as recorded in the survey.
    let heightM: Float
    /// Trunk circumference in centimetres.
    let girthCm: Int
    let ward: String
    let roadName: String
}

/// The trees, and the species table their colours are indexed by.
struct StreetTreeData {
    let trees: [StreetTree]
    let species: [String]
}

struct StreetTreeDataLoader {
    /// Magic, then a version byte the reader checks by length rather than value.
    private static let magic = "TREE"
    private static let headerBytes = 5
    /// lat, lon, species, height, girth, ward, road.
    private static let recordBytes = 20

    /// Reads the packed asset: the magic, three string tables, then one fixed
    /// record per tree, all little-endian.
    ///
    /// The source is a 12 MB Shift-JIS CSV; parsing that on the device would
    /// measure CSV parsing rather than the map, and the packed form is 2.8 MB.
    /// android-sdk and the web SDK read the same bytes.
    func load() async -> StreetTreeData {
        await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "tokyo-trees", withExtension: "bin"),
                  let data = try? Data(contentsOf: url) else {
                print("[StreetTreeDataLoader] tokyo-trees.bin is not in the bundle")
                return StreetTreeData(trees: [], species: [])
            }
            return Self.decode(data)
        }.value
    }

    static func decode(_ data: Data) -> StreetTreeData {
        let bytes = [UInt8](data)
        guard bytes.count > headerBytes,
              String(decoding: bytes[0..<magic.utf8.count], as: UTF8.self) == magic else {
            print("[StreetTreeDataLoader] unexpected street tree asset format")
            return StreetTreeData(trees: [], species: [])
        }
        var at = headerBytes

        func uint16() -> Int {
            defer { at += 2 }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        func uint32() -> Int {
            defer { at += 4 }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8
                | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        func float32(_ offset: Int) -> Float {
            let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            return Float(bitPattern: raw)
        }
        func table() -> [String] {
            let count = uint32()
            var names: [String] = []
            names.reserveCapacity(count)
            for _ in 0..<count {
                let length = uint16()
                names.append(String(decoding: bytes[at..<(at + length)], as: UTF8.self))
                at += length
            }
            return names
        }

        let species = table()
        let wards = table()
        let roads = table()

        let count = uint32()
        var trees: [StreetTree] = []
        trees.reserveCapacity(count)
        for _ in 0..<count {
            let speciesIndex = Int(bytes[at + 8]) | Int(bytes[at + 9]) << 8
            let ward = Int(bytes[at + 16]) | Int(bytes[at + 17]) << 8
            let road = Int(bytes[at + 18]) | Int(bytes[at + 19]) << 8
            trees.append(
                StreetTree(
                    position: GeoPoint(
                        latitude: Double(float32(at)),
                        longitude: Double(float32(at + 4))
                    ),
                    species: species[speciesIndex],
                    speciesIndex: speciesIndex,
                    heightM: float32(at + 10),
                    girthCm: Int(bytes[at + 14]) | Int(bytes[at + 15]) << 8,
                    ward: wards[ward],
                    roadName: roads[road]
                )
            )
            at += recordBytes
        }
        return StreetTreeData(trees: trees, species: species)
    }
}

/// 点のどちら側にラベルを描くか。
enum LabelSide: Hashable { case right, left, top, bottom }

enum StreetTreeIcons {
    /// ラベルの文字の大きさ（pt）。ラベルの重なり判定もこの値で測る。
    static let labelTextPt: CGFloat = 11
    /// 点とラベルのすき間（pt）。SDK の配置（縁取りの太さ 2pt）と同じ値。
    static let labelGapPt: CGFloat = 2
    /// 縁取りの太さ（pt）。SDK はラベルの幅と高さにこの 2 倍を足す。
    private static let labelOutlinePt: CGFloat = 2

    static let labelFont = UIFont.boldSystemFont(ofSize: labelTextPt)
    private static let cacheLock = NSLock()
    private static var labelSizes: [String: CGSize] = [:]

    /// 点の上下に置くラベルは縦書きにする。横の通りでは点が横に詰まって並ぶので、
    /// 横書きだと数本に 1 つしか名前を付けられない。
    static func isVertical(_ side: LabelSide) -> Bool { side == .top || side == .bottom }

    /// ラベルの幅と高さ（pt、縁取りを含む）。樹種名と向きごとに 1 回だけ測る。
    /// SDK と同じく CoreText で 1 行に組んで測る（縦書きは縦組みの字形で）。
    static func labelSize(_ text: String, vertical: Bool) -> CGSize {
        let key = vertical ? "v/\(text)" : "h/\(text)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let size = labelSizes[key] { return size }
        var attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        if vertical { attributes[.verticalGlyphForm] = true }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let length = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let size = vertical
            ? CGSize(
                width: ceil(CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).height) + labelOutlinePt * 2,
                height: ceil(length) + labelOutlinePt * 2
            )
            : CGSize(width: ceil(length) + labelOutlinePt * 2, height: ceil(ascent + descent) + labelOutlinePt * 2)
        labelSizes[key] = size
        return size
    }

    /// 点の `side` 側に樹種名を添えたアイコン。
    ///
    /// SDK の `ImageIcon` のラベルを使う。画像は作らない -- タイル描画は点の画像と
    /// 文字を別々に描くので、ラベル付きのアイコンをいくつ作っても点の画像は 1 枚のまま。
    static func labelled(_ dot: ImageIcon, text: String, side: LabelSide) -> ImageIcon {
        let position: String
        switch side {
        case .right: position = "right"
        case .left: position = "left"
        case .top: position = "top"
        case .bottom: position = "bottom"
        }
        return dot.copy(
            label: text,
            labelTextColor: UIColor(white: 0.16, alpha: 1),
            labelTextSize: labelTextPt,
            labelTypeFace: labelFont,
            labelStrokeColor: .white,
            labelPosition: position,
            labelWritingMode: isVertical(side) ? "vertical-rl" : "horizontal-tb"
        )
    }

    /// One coloured dot per species, shared by every tree of that species.
    ///
    /// Baked once. Building an icon per marker would measure icon generation
    /// rather than drawing, and there are 144,183 markers against a hundred or
    /// so species.
    /// [sizePt] は **ポイント**。`UIGraphicsImageRenderer` は既定で端末スケールの
    /// 画素を作るので、ここでポイントを渡せば密度非依存になる -- core の
    /// `ColorDefaultIcon` が `canvasSize = iconSize * scale` でそうしているのと
    /// 同じ流儀。android-sdk は dp、web は CSS px で同じ 10 を使う。
    static func palette(count: Int, sizePt: CGFloat = 10) -> [ImageIcon] {
        (0..<count).map { index in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: sizePt, height: sizePt))
            let image = renderer.image { context in
                let inset = CGRect(x: 0.5, y: 0.5, width: sizePt - 1, height: sizePt - 1)
                colour(index: index, count: count).setFill()
                context.cgContext.fillEllipse(in: inset)
                UIColor(white: 0, alpha: 0.43).setStroke()
                context.cgContext.setLineWidth(1)
                context.cgContext.strokeEllipse(in: inset)
            }
            return ImageIcon(
                image: image,
                iconSize: sizePt,
                anchor: CGPoint(x: 0.5, y: 0.5),
                infoAnchor: CGPoint(x: 0.5, y: 0.0)
            )
        }
    }

    /// Golden-angle hue rotation, so neighbouring species indices do not come
    /// out as neighbouring colours. The last entry is the "other" bucket, which
    /// reads as grey rather than competing with a named species for a hue.
    ///
    /// Matches android-sdk's StreetTreeIcons and the web sample's treeIcons, so
    /// a species is the same colour on all three.
    static func colour(index: Int, count: Int) -> UIColor {
        if index == count - 1 {
            return UIColor(red: 150 / 255, green: 150 / 255, blue: 155 / 255, alpha: 1)
        }
        let hue = (Double(index) * 137.508).truncatingRemainder(dividingBy: 360) / 360
        return UIColor(hue: hue, saturation: 0.70, brightness: 0.80, alpha: 1)
    }
}

// MARK: - ラベルの配置


/// 画面内の街路樹のうち、どれにどちら向きのラベルを付けるか。
///
/// - 向きは**道路ごとに 1 つ**。道路の木の並びが横向きなら上か下、縦向きなら右か左
///   （道路に直交する向き）。同じ通りのラベルが揃って並ぶ。
/// - 2 つの候補のうち、置けるラベルが多い方を選ぶ。木の多い道路から決める。
///   ただし前回その道路で選んだ向き（`previousSides`）は、もう一方の 2/3 以上置けるなら
///   そのまま使う。見えている範囲が変わるたびに数の多い方へ乗り換えると、パンするたびに
///   ラベルが上下や左右で入れ替わる。
/// - すでに置いたラベルか、ほかの木の点の中心を覆うラベルは付けない（その木は点のまま）。
///   ラベルは点の後に描かれるので、端が隣の点に少しかかるのは許す。
/// - 上下に置くラベルは縦書き（`StreetTreeIcons.isVertical`）なので、縦書きの寸法で測る。
///
/// 座標はカメラのズームでの pt。android-sdk の `StreetTreeLabels` と同じ手順。
enum StreetTreeLabels {
    /// `trees` の添字 -> 向き。
    static func choose(
        trees: [StreetTree],
        bounds: GeoRectBounds,
        zoom: Double,
        /// ラベルのアイコンに掛かる倍率（タイルの iconScaleCallback と同じ値）。
        scale: Double,
        dotSizePt: Double,
        labelSize: (String, Bool) -> CGSize,
        /// 前回の道路名 -> 向き。
        previousSides: [String: LabelSide] = [:]
    ) -> [Int: LabelSide] {
        guard let southWest = bounds.southWest, let northEast = bounds.northEast else { return [:] }
        let world = 256.0 * pow(2.0, zoom)
        func x(_ longitude: Double) -> Double { (longitude + 180.0) / 360.0 * world }
        func y(_ latitude: Double) -> Double {
            let phi = latitude * .pi / 180.0
            return (1.0 - log(tan(phi) + 1.0 / cos(phi)) / .pi) / 2.0 * world
        }

        // 道路ごとの、画面内の木
        var byRoad: [String: [Int]] = [:]
        for (index, tree) in trees.enumerated() {
            let p = tree.position
            if p.latitude < southWest.latitude || p.latitude > northEast.latitude { continue }
            if p.longitude < southWest.longitude || p.longitude > northEast.longitude { continue }
            byRoad[tree.roadName, default: []].append(index)
        }

        let radius = dotSizePt * scale / 2
        let gap = Double(StreetTreeIcons.labelGapPt) * scale

        // 画面内のすべての点の中心。ラベルは点の後に描くので、端が隣の点に少しかかるのは許し、
        // 点の中心を覆うものだけを捨てる。点の箱ごと避けると、木の間隔が詰まった斜めの通りでは
        // 隣の点がどの向きの箱にもかかり、ラベルが 1 つも置けない。
        var dots = PlacedRects()
        for members in byRoad.values {
            for index in members {
                let cx = x(trees[index].position.longitude)
                let cy = y(trees[index].position.latitude)
                dots.add(Rect(left: cx - 0.5, top: cy - 0.5, right: cx + 0.5, bottom: cy + 0.5))
            }
        }

        var placed = PlacedRects()
        var sides: [Int: LabelSide] = [:]

        for (road, members) in byRoad.sorted(by: { $0.value.count > $1.value.count }) {
            let xs = members.map { x(trees[$0].position.longitude) }
            let ys = members.map { y(trees[$0].position.latitude) }

            // 並びの向き（主成分）
            let mx = xs.reduce(0, +) / Double(xs.count)
            let my = ys.reduce(0, +) / Double(ys.count)
            var sxx = 0.0, syy = 0.0, sxy = 0.0
            for i in xs.indices {
                let dx = xs[i] - mx, dy = ys[i] - my
                sxx += dx * dx
                syy += dy * dy
                sxy += dx * dy
            }
            let angle = 0.5 * atan2(2 * sxy, sxx - syy)
            let horizontal = abs(cos(angle)) >= abs(sin(angle))
            let candidates: [LabelSide] = horizontal ? [.top, .bottom] : [.right, .left]

            // 道路に沿って並べてから置いていく
            let order = xs.indices.sorted { xs[$0] * cos(angle) + ys[$0] * sin(angle) < xs[$1] * cos(angle) + ys[$1] * sin(angle) }

            func rect(_ i: Int, _ side: LabelSide) -> Rect {
                let size = labelSize(trees[members[i]].species, StreetTreeIcons.isVertical(side))
                let w = Double(size.width) * scale
                let h = Double(size.height) * scale
                let cx = xs[i], cy = ys[i]
                switch side {
                case .right: return Rect(left: cx + radius + gap, top: cy - h / 2, right: cx + radius + gap + w, bottom: cy + h / 2)
                case .left: return Rect(left: cx - radius - gap - w, top: cy - h / 2, right: cx - radius - gap, bottom: cy + h / 2)
                case .top: return Rect(left: cx - w / 2, top: cy - radius - gap - h, right: cx + w / 2, bottom: cy - radius - gap)
                case .bottom: return Rect(left: cx - w / 2, top: cy + radius + gap, right: cx + w / 2, bottom: cy + radius + gap + h)
                }
            }

            func attempt(_ side: LabelSide) -> [(Int, Rect)] {
                var own = PlacedRects()
                var accepted: [(Int, Rect)] = []
                for i in order {
                    let r = rect(i, side)
                    if placed.overlaps(r) || own.overlaps(r) || dots.overlaps(r) { continue }
                    own.add(r)
                    accepted.append((i, r))
                }
                return accepted
            }

            let attempts = candidates.map { ($0, attempt($0)) }
            let most = attempts.max { $0.1.count < $1.1.count }!
            let kept = attempts.first { $0.0 == previousSides[road] }
            let best = kept.map { $0.1.count * 3 >= most.1.count * 2 ? $0 : most } ?? most
            for (i, r) in best.1 {
                placed.add(r)
                sides[members[i]] = best.0
            }
        }
        return sides
    }

    private struct Rect {
        let left: Double, top: Double, right: Double, bottom: Double
        func overlaps(_ other: Rect) -> Bool {
            left < other.right && other.left < right && top < other.bottom && other.top < bottom
        }
    }

    /// 置いたラベルの箱。64pt のマス目に振り分けて、近くだけを見る。
    private struct PlacedRects {
        private static let cell = 64.0
        private var cells: [Int64: [Rect]] = [:]

        private func keys(_ r: Rect) -> [Int64] {
            var out: [Int64] = []
            for cx in Int64(floor(r.left / Self.cell))...Int64(floor(r.right / Self.cell)) {
                for cy in Int64(floor(r.top / Self.cell))...Int64(floor(r.bottom / Self.cell)) {
                    out.append((cx << 32) ^ (cy & 0xFFFF_FFFF))
                }
            }
            return out
        }

        func overlaps(_ r: Rect) -> Bool {
            keys(r).contains { key in cells[key]?.contains { $0.overlaps(r) } == true }
        }

        mutating func add(_ r: Rect) {
            for key in keys(r) { cells[key, default: []].append(r) }
        }
    }
}
