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

enum StreetTreeIcons {
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
    private static func colour(index: Int, count: Int) -> UIColor {
        if index == count - 1 {
            return UIColor(red: 150 / 255, green: 150 / 255, blue: 155 / 255, alpha: 1)
        }
        let hue = (Double(index) * 137.508).truncatingRemainder(dividingBy: 360) / 360
        return UIColor(hue: hue, saturation: 0.70, brightness: 0.80, alpha: 1)
    }
}
