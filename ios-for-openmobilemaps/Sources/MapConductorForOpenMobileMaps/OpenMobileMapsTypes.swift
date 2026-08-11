import Foundation
import MapCore
import MapConductorCore
import UIKit

/*
 * 「地図に載っている実体」の型と、MapConductor ⇄ SDK の値の変換。
 *
 * ## ActualXxx はコアが id で引き当てるための持ち手にすぎない
 *
 * コアの Manager は `ActualXxx` の中身を一切見ない。レンダラが `onAdd` で作って返し、
 * `onChange` / `onRemove` で受け取る。したがって「SDK の描画オブジェクトそのもの」を
 * そのまま入れるのが一番素直である。Open Mobile Maps はレイヤが
 * `MCIconInfoInterface` / `MCLineInfoInterface` / `MCPolygonInfo` のリストを持つ形なので、
 * その要素をそのまま Actual として扱う。
 *
 * android-for-openmobilemaps の `OpenMobileMapsTypes.kt` と同じ並び。
 */

/// 地図上のマーカー 1 つ。SDK の `MCIconInfoInterface` そのもの。
public typealias OpenMobileMapsActualMarker = MCIconInfoInterface

/// 地図上のポリライン 1 本。
///
/// 1 本のポリラインが**複数の `MCLineInfoInterface` になる**ことがある。geodesic な線を
/// 密度化したうえで子午線で分割すると、±180° を跨ぐ線が 2 本以上のセグメントに割れるため。
public typealias OpenMobileMapsActualPolyline = [MCLineInfoInterface]

/// 塗りと輪郭の組。Open Mobile Maps のポリゴンレイヤは輪郭線を描かないので線レイヤと併用する。
public struct OpenMobileMapsActualPolygon {
    public let fills: [MCPolygonInfo]
    public let outlines: [MCLineInfoInterface]
}

/// 円。SDK に円の概念が無いのでポリゴン + 輪郭線として描く。
public struct OpenMobileMapsActualCircle {
    public let fills: [MCPolygonInfo]
    public let outlines: [MCLineInfoInterface]
}

/// グラウンドイメージ。SDK の「テクスチャ付きポリゴンレイヤ」1 枚に対応する。
///
/// `layerInterface` を持っているのは、`asLayerInterface()` が**呼ぶたびに別のオブジェクトを
/// 返す**ため（`OpenMobileMapsLayers` のコメント参照）。載せたときの値をそのまま持っておかないと
/// 地図から外せない。
public struct OpenMobileMapsActualGroundImage {
    public let layer: MCTexturedPolygonLayerInterface
    public let layerInterface: MCLayerInterface
}

/// ラスターレイヤ。`layerInterface` を持つ理由は ``OpenMobileMapsActualGroundImage`` と同じ。
public struct OpenMobileMapsActualRasterLayer {
    public let layer: MCTiled2dMapRasterLayerInterface
    public let layerInterface: MCLayerInterface
}

// ── 座標 ──────────────────────────────────────────────────────────────────

extension GeoPointProtocol {
    /// MapConductor の座標 → SDK の `MCCoord`。
    ///
    /// EPSG:4326 では **x が経度・y が緯度**。MapConductor は latitude / longitude の順なので、
    /// 取り違えても例外にならず「座標が入れ替わるだけ」になり、原因が非常に追いにくい。
    /// 変換をこの 1 箇所に閉じ込めているのはそのため。
    var ommCoord: MCCoord {
        MCCoord(
            systemIdentifier: MCCoordinateSystemIdentifiers.epsg4326(),
            x: longitude,
            y: latitude,
            z: altitude ?? 0.0
        )
    }
}

extension MCCoord {
    /// SDK の `MCCoord` → MapConductor の座標。
    var geoPoint: GeoPoint { GeoPoint(latitude: y, longitude: x, altitude: z) }
}

extension Array where Element == any GeoPointProtocol {
    /// 点列 → SDK の座標列。
    var ommCoords: [MCCoord] { map(\.ommCoord) }
}

/// 外周リングと穴リング → SDK の `MCPolygonCoord`。
///
/// Open Mobile Maps は**穴をネイティブに持てる**（`MCPolygonCoord.holes`）数少ない SDK。
/// 穴をブリッジで外周に繋ぐ細工（コアの `bridgeHolesIntoSingleRing`）は要らない。
func polygonCoord(
    outer: [any GeoPointProtocol],
    holes: [[any GeoPointProtocol]]
) -> MCPolygonCoord {
    MCPolygonCoord(
        positions: outer.map(\.ommCoord),
        holes: holes.map { $0.map(\.ommCoord) }
    )
}

// ── 色 ────────────────────────────────────────────────────────────────────

extension UIColor {
    /// UIKit の色 → SDK の色。
    ///
    /// SDK 側は 0..1 の float 4 つ。**アルファ済み（premultiplied）ではない**ので、
    /// そのまま渡してよい。
    var ommColor: MCColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return MCColor(r: Float(red), g: Float(green), b: Float(blue), a: Float(alpha))
    }
}

/// 完全透明。「塗らない」の意味で使う。
func transparentOmmColor() -> MCColor { MCColor(r: 0, g: 0, b: 0, a: 0) }
