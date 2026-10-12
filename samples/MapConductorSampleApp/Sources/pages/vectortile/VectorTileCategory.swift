import MapConductorVectorStyle
import SwiftUI

/**
 ベクタータイルのサンプルで触れる「地図の上のもの」と、それが指すスタイルの
 中の role。

 1 つに role が複数あるのは、**つまみは地図の上のもの、role はスタイルの中の
 もの**だから。人が「陸」と呼ぶのは地図が乗っている背景（`background`）＋その
 上の土地利用（`land`）＋敷地（`landuse`）で、真ん中だけ消したり塗ったりしても
 地面の色は変わらない。「水域」も面と川筋の両方。

 レイヤー id ではなく role で指すので、別のスタイルに差し替えても同じ言葉が
 通る。android-sdk の `VectorTileCategory` と react-sdk の
 `VectorTileLayerPage` も同じ並び・同じ既定色。
 */
struct VectorTileCategory: Identifiable {
    let label: String
    let key: String
    let roles: [String]
    /**
     The colour this category starts at, or nil when it cannot be painted.

     Only labels are nil. The tint pulls every matched layer towards one
     colour, and doing that to text would flatten the whole legend — the
     green of a park's name, the blue of a river's — by merely opening the
     page. Switching them off is what a label knob is wanted for.
     */
    let defaultColor: Color?

    var id: String { key }

    static let all: [VectorTileCategory] = [
        VectorTileCategory(
            label: "Water", key: "water",
            roles: [LayerRole.water, LayerRole.waterway],
            defaultColor: Color(red: 0.23, green: 0.49, blue: 0.65)
        ),
        VectorTileCategory(
            label: "Land", key: "land",
            roles: [LayerRole.background, LayerRole.land, LayerRole.landuse],
            defaultColor: Color(red: 0.95, green: 0.94, blue: 0.90)
        ),
        // 縁取りは road でもあるので、これで一緒に拾える。
        VectorTileCategory(
            label: "Roads", key: "road",
            roles: [LayerRole.road],
            defaultColor: Color.white
        ),
        VectorTileCategory(
            label: "Buildings", key: "building",
            roles: [LayerRole.building],
            defaultColor: Color(red: 0.85, green: 0.82, blue: 0.79)
        ),
        // Every symbol layer: place names, POIs, road shields, the one-way
        // arrows painted along a street. On the raster path these are the
        // transparent overlay, so switching them off empties that half.
        VectorTileCategory(
            label: "Labels", key: "label",
            roles: [LayerRole.label],
            defaultColor: nil
        ),
    ]

    static var defaultPalette: [String: Color] {
        Dictionary(uniqueKeysWithValues: all.compactMap { category in
            category.defaultColor.map { (category.key, $0) }
        })
    }

    /**
     The palette to start with, overridable per key by
     `MAPCONDUCTOR_SAMPLE_PALETTE` (`water:#e65100,road:#000000`).

     A UI test cannot drive the system colour sheet without becoming a test
     of the sheet, so the picked colour is settable at launch and the test
     compares two runs.
     */
    static var initialPalette: [String: Color] {
        var palette = defaultPalette
        let text = ProcessInfo.processInfo.environment["MAPCONDUCTOR_SAMPLE_PALETTE"] ?? ""
        for pair in text.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let colour = Color(styleHex: String(parts[1])) else { continue }
            palette[String(parts[0])] = colour
        }
        return palette
    }

    /**
     つまみの状態をそのままルールにしたもの。

     外した種別はレイヤーごと落ちるので**描かれない**（背景と同じ色を塗るので
     はない）。色は `mix` で元の色から寄せる: 本物のベースマップは森・草地・
     農地を十数通りの緑で描き分けていて、1 色に潰すとその差が消えて地図に
     見えなくなる。強さ 0 なら何も書かず、文書は作者が書いたままになる。
     */
    static func rules(
        hiding hidden: Set<String>,
        palette: [String: Color],
        strength: Double
    ) -> StyleRules {
        let gone = all.filter { hidden.contains($0.key) }
        guard !gone.isEmpty || strength > 0 else { return .none }
        return StyleRules.build { rules in
            for role in gone.flatMap(\.roles).sorted() {
                rules.role(role) { $0.visible = false }
            }
            guard strength > 0 else { return }
            for category in all where !hidden.contains(category.key) {
                guard let colour = palette[category.key] ?? category.defaultColor else { continue }
                let target = UIColor(colour)
                for role in category.roles {
                    rules.role(role) { $0.mix(target, amount: strength) }
                }
            }
        }
    }
}

private extension Color {
    /// `#rrggbb`. Nil for anything else — a bad launch argument must not
    /// silently become black.
    init?(styleHex text: String) {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
