import Foundation
import MapCore

/// このドライバーが地図に載せるレイヤ一式と、その重ね順。
///
/// ## なぜレイヤを 1 箇所で持つのか
///
/// Open Mobile Maps は「オーバーレイ 1 つ = ネイティブオブジェクト 1 つ」ではなく
/// 「**種別ごとに 1 枚のレイヤ**があり、そこへ要素のリストを流し込む」形の SDK である
/// （MapLibre の GeoJSON ソースに近い）。レンダラが個別にレイヤを作ると重ね順が
/// 生成順に依存して不定になるので、ここでまとめて作り、索引を割り当てる。
///
/// ## 重ね順（下から）
///
/// ```
/// 地図デザイン → ラスターレイヤ・グラウンドイメージ → ポリゴン塗り → ポリゴン輪郭
///   → 円の塗り → 円の輪郭 → ポリライン → マーカー
/// ```
///
/// 他プロバイダのクリックのカスケード（marker → circle → groundImage → polyline →
/// polygon → map）と**上下が逆に見える**が、これは正しい。カスケードは「上にあるものから
/// 順に当たり判定する」ので、描画の重ね順を上から読むとカスケード順に一致する。
///
/// ## この SDK のレイヤ API には罠が 2 つある
///
/// **1. `insertLayer(at:at:)` は挿入ではなく上書きである。**
/// `MapScene` はレイヤを「索引 → レイヤ」の map で持っていて、その索引に居たレイヤを
/// `onRemoved()` して置き換える。地図デザインを索引 0 に入れると、索引 0 に居た
/// **ポリゴン塗りレイヤが黙って外れる**。症状は「円は塗れるのにポリゴンだけ塗れない」で、
/// 例外もログも出ない。だから索引は ``designIndex`` / ``belowIndexFirst`` /
/// ``fixedIndexFirst`` に分けて**衝突させない**。
///
/// **2. `asLayerInterface()` は呼ぶたびに別のオブジェクトを返す。**
/// `insertLayer(below:below: polygonFillLayer.asLayerInterface())` は「そんなレイヤは無い」で
/// 落ちる。`removeLayer` も黙って何も外さない。載せたときの値を持っておいて、それを渡すこと。
///
/// android-for-openmobilemaps の `OpenMobileMapsLayers.kt` と同じ構造・同じ索引。
@MainActor
final class OpenMobileMapsLayers {
    /// 地図デザイン。一番下。
    private static let designIndex: Int32 = 0

    /// ラスターレイヤ・グラウンドイメージ。地図デザインとオーバーレイ群の間。
    private static let belowIndexFirst: Int32 = 1

    /// 固定のオーバーレイ 6 種。下の枠を使い切らないよう十分離す。
    private static let fixedIndexFirst: Int32 = 1000

    let polygonFillLayer = MCPolygonLayerInterface.create()
    let polygonOutlineLayer = MCLineLayerInterface.create()
    let circleFillLayer = MCPolygonLayerInterface.create()
    let circleOutlineLayer = MCLineLayerInterface.create()
    let polylineLayer = MCLineLayerInterface.create()
    let iconLayer = MCIconLayerInterface.create()

    /// 地図デザインのレイヤ。差し替え時に外すため、**載せた値そのもの**を持っておく。
    private var designLayer: MCLayerInterface?

    /// 地図デザインとオーバーレイ群の間に入っているレイヤ（ラスター / グラウンドイメージ）と、その索引。
    private var belowOverlayIndices: [ObjectIdentifier: Int32] = [:]

    /// 外したレイヤの索引。使い回さないと、タイルの張り替えを繰り返すうちに索引が尽きる。
    private var freeBelowIndices: [Int32] = []
    private var nextBelowIndex = OpenMobileMapsLayers.belowIndexFirst

    /// `asLayerInterface()` の戻りを**一度だけ**取って持っておく（罠 2）。
    private lazy var fixedLayers: [MCLayerInterface] = [
        polygonFillLayer?.asLayerInterface(),
        polygonOutlineLayer?.asLayerInterface(),
        circleFillLayer?.asLayerInterface(),
        circleOutlineLayer?.asLayerInterface(),
        polylineLayer?.asLayerInterface(),
        iconLayer?.asLayerInterface(),
    ].compactMap { $0 }

    /// 固定レイヤを地図へ載せる。
    ///
    /// ## クリックは SDK に取らせない
    ///
    /// どのレイヤも `setLayerClickable(false)` にする。当たり判定はコアの Manager が
    /// 地理座標で行う（そうしないとプロバイダごとに結果が変わる）ので、SDK 側の
    /// ヒットテストが先に食べてしまうと `clickable = false` の透過もカスケードの順序も
    /// 効かなくなる。**ここを消すと「ポリゴンをタップしても下のマーカーに当たらない」
    /// という形で壊れる。**
    func attach(to map: MCMapInterface) {
        polygonFillLayer?.setLayerClickable(false)
        circleFillLayer?.setLayerClickable(false)
        polygonOutlineLayer?.setLayerClickable(false)
        circleOutlineLayer?.setLayerClickable(false)
        polylineLayer?.setLayerClickable(false)
        iconLayer?.setLayerClickable(false)

        for (offset, layer) in fixedLayers.enumerated() {
            map.insertLayer(at: layer, at: Self.fixedIndexFirst + Int32(offset))
        }
    }

    /// 地図デザインのレイヤを差し替える。
    func setDesignLayer(_ layer: MCLayerInterface?, on map: MCMapInterface) {
        if let designLayer { map.removeLayer(designLayer) }
        designLayer = layer
        guard let layer else { return }
        map.insertLayer(at: layer, at: Self.designIndex)
    }

    /// ラスターレイヤ／グラウンドイメージを、オーバーレイ群より下・地図デザインより上へ入れる。
    ///
    /// - Returns: 外すときに ``remove(_:from:)`` へ渡す値。
    ///   **別途 `asLayerInterface()` を呼び直さないこと。**
    @discardableResult
    func insertBelowOverlays(_ layer: MCLayerInterface, on map: MCMapInterface) -> MCLayerInterface {
        let index: Int32
        if freeBelowIndices.isEmpty {
            index = nextBelowIndex
            nextBelowIndex += 1
        } else {
            index = freeBelowIndices.removeFirst()
        }
        belowOverlayIndices[ObjectIdentifier(layer)] = index
        map.insertLayer(at: layer, at: index)
        return layer
    }

    func remove(_ layer: MCLayerInterface, from map: MCMapInterface) {
        if let index = belowOverlayIndices.removeValue(forKey: ObjectIdentifier(layer)) {
            freeBelowIndices.append(index)
            freeBelowIndices.sort()
        }
        map.removeLayer(layer)
    }

    func clearAll() {
        polygonFillLayer?.clear()
        polygonOutlineLayer?.clear()
        circleFillLayer?.clear()
        circleOutlineLayer?.clear()
        polylineLayer?.clear()
        iconLayer?.clear()
    }
}
