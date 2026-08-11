import CoreGraphics
import Foundation
import MapCore
import MapConductorCore
import UIKit

/*
 * オーバーレイのレンダラとコントローラ。**ドライバーが本当に書くのはこのファイル**である。
 *
 * ## この SDK の描画モデル
 *
 * Open Mobile Maps は「オーバーレイ 1 つ = ネイティブオブジェクト 1 つ」ではなく、
 * **種別ごとに 1 枚のレイヤがあり、そこへ要素のリストを流し込む**形（MapLibre の
 * GeoJSON ソースに近い）。したがって各レンダラは
 *
 *   createXxx / updateXxx … 要素（`MCIconInfoInterface` / `MCLineInfoInterface` /
 *                            `MCPolygonInfo`）を作る
 *   onPostProcess         … マネージャの全要素を集めてレイヤへ一括で流す
 *
 * という形になる。個別の `removeXxx` でレイヤを触らないのは、どのみち
 * `onPostProcess` で全量を流し直すためである。
 *
 * ## 当たり判定・カスケード・ドラッグの状態遷移は書かない
 *
 * すべてコアが持っている。このファイルにあるのは「MapConductor の State を
 * SDK の型へ翻訳する」ことだけ。
 *
 * android-for-openmobilemaps の `OpenMobileMapsOverlays.kt` と同じ構成。
 */

// ── ポリライン ────────────────────────────────────────────────────────────

/// ポリラインのレンダラ。
///
/// 1 本のポリラインが複数の `MCLineInfoInterface` になり得る（geodesic を密度化してから
/// 子午線で分割するため）。``OpenMobileMapsActualPolyline`` がリストなのはそのため。
@MainActor
final class OpenMobileMapsPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<OpenMobileMapsActualPolyline> {
    private let polylineManager: PolylineManager<OpenMobileMapsActualPolyline>
    private weak var lineLayer: MCLineLayerInterface?

    init(
        polylineManager: PolylineManager<OpenMobileMapsActualPolyline>,
        lineLayer: MCLineLayerInterface?
    ) {
        self.polylineManager = polylineManager
        self.lineLayer = lineLayer
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> OpenMobileMapsActualPolyline? {
        buildPolylineSegments(state.points, geodesic: state.geodesic)
            .enumerated()
            .compactMap { index, segment in
                MCLineFactory.createLine(
                    "polyline-\(state.id)-\(index)",
                    coordinates: segment.map(\.ommCoord),
                    style: strokeStyle(color: state.strokeColor, width: state.strokeWidth)
                )
            }
    }

    override func updatePolylineProperties(
        polyline _: OpenMobileMapsActualPolyline,
        current: PolylineEntity<OpenMobileMapsActualPolyline>,
        prev _: PolylineEntity<OpenMobileMapsActualPolyline>
    ) async -> OpenMobileMapsActualPolyline? {
        await createPolyline(state: current.state)
    }

    override func removePolyline(entity _: PolylineEntity<OpenMobileMapsActualPolyline>) async {}

    override func onPostProcess() async {
        lineLayer?.setLines(polylineManager.allEntities().flatMap { $0.polyline ?? [] })
    }

    func unbind() { lineLayer = nil }
}

// ── ポリゴン ──────────────────────────────────────────────────────────────

/// ポリゴンのレンダラ。
///
/// ## 穴はネイティブに渡せる
///
/// Open Mobile Maps の `MCPolygonCoord` は穴リングをそのまま持てるので、穴をブリッジで
/// 外周に繋ぐ細工は要らない。ただし**穴どうしが重なっている場合は先に結合する**
/// （`unionHoles()`）。重なった穴をそのまま渡すと、テッセレータの塗り規則しだいで
/// 重なり部分が「穴の穴」として塗り戻される。
///
/// ## 輪郭線は線レイヤで描く
///
/// `MCPolygonLayerInterface` は塗りだけで輪郭を持たない。他プロバイダと見た目を揃えるため、
/// 外周と穴のリングを `MCLineLayerInterface` にも流す。
@MainActor
final class OpenMobileMapsPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<OpenMobileMapsActualPolygon> {
    private let polygonManager: PolygonManager<OpenMobileMapsActualPolygon>
    private weak var fillLayer: MCPolygonLayerInterface?
    private weak var outlineLayer: MCLineLayerInterface?

    init(
        polygonManager: PolygonManager<OpenMobileMapsActualPolygon>,
        fillLayer: MCPolygonLayerInterface?,
        outlineLayer: MCLineLayerInterface?
    ) {
        self.polygonManager = polygonManager
        self.fillLayer = fillLayer
        self.outlineLayer = outlineLayer
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> OpenMobileMapsActualPolygon? {
        let resolved = state.holes.count > 1 ? state.unionHoles() : state
        let rings = buildPolygonRings(points: resolved.points, holes: resolved.holes, geodesic: resolved.geodesic)

        let fills = rings.outerRings.enumerated().map { index, outer in
            MCPolygonInfo(
                identifier: "polygon-\(resolved.id)-\(index)",
                coordinates: polygonCoord(
                    // 巻き方向を揃えること。SDK のテッセレータは外周 CCW / 穴 CW を前提に
                    // していて、逆向きのリングは**塗りが丸ごと消える**（例外も警告も出ない）。
                    // android では「円が塗れてポリゴンが塗れない」という形で最初に出た。
                    outer: ensureCounterClockwise(outer),
                    holes: rings.holeRings.map { ensureClockwiseRing($0) }
                ),
                color: resolved.fillColor.ommColor,
                highlight: resolved.fillColor.ommColor
            )
        }

        let outlines = (rings.outerRings + rings.holeRings).enumerated().compactMap { index, ring in
            MCLineFactory.createLine(
                "polygon-outline-\(resolved.id)-\(index)",
                coordinates: closeRing(ring).map(\.ommCoord),
                style: strokeStyle(color: resolved.strokeColor, width: resolved.strokeWidth)
            )
        }

        return OpenMobileMapsActualPolygon(fills: fills, outlines: outlines)
    }

    override func updatePolygonProperties(
        polygon _: OpenMobileMapsActualPolygon,
        current: PolygonEntity<OpenMobileMapsActualPolygon>,
        prev _: PolygonEntity<OpenMobileMapsActualPolygon>
    ) async -> OpenMobileMapsActualPolygon? {
        await createPolygon(state: current.state)
    }

    override func removePolygon(entity _: PolygonEntity<OpenMobileMapsActualPolygon>) async {}

    override func onPostProcess() async {
        let entities = polygonManager.allEntities()
        // add ではなく setPolygons を使うこと。4.0 の PolygonLayer は原点（第 2 引数）を
        // 持つようになっていて、setPolygons を一度も通っていないレイヤに add すると
        // **何も描かれない**（例外も警告も出ない）。
        fillLayer?.setPolygons(entities.flatMap { $0.polygon?.fills ?? [] }, origin: renderOrigin)
        outlineLayer?.setLines(entities.flatMap { $0.polygon?.outlines ?? [] })
    }

    func unbind() {
        fillLayer = nil
        outlineLayer = nil
    }
}

// ── 円 ────────────────────────────────────────────────────────────────────

/// 円のレンダラ。SDK に円の描画が無いので、コア共通の `circleToRing` でリングに直して
/// ポリゴンとして描く（他プロバイダと同じ分割数・同じ測地線の扱いになる）。
@MainActor
final class OpenMobileMapsCircleOverlayRenderer: AbstractCircleOverlayRenderer<OpenMobileMapsActualCircle> {
    private let circleManager: CircleManager<OpenMobileMapsActualCircle>
    private weak var fillLayer: MCPolygonLayerInterface?
    private weak var outlineLayer: MCLineLayerInterface?

    init(
        circleManager: CircleManager<OpenMobileMapsActualCircle>,
        fillLayer: MCPolygonLayerInterface?,
        outlineLayer: MCLineLayerInterface?
    ) {
        self.circleManager = circleManager
        self.fillLayer = fillLayer
        self.outlineLayer = outlineLayer
        super.init()
    }

    override func createCircle(state: CircleState) async -> OpenMobileMapsActualCircle? {
        let ring = circleToRing(center: state.center, radiusMeters: state.radiusMeters, geodesic: state.geodesic)
        guard ring.count >= 3 else { return nil }

        let fill = MCPolygonInfo(
            identifier: "circle-\(state.id)",
            coordinates: polygonCoord(outer: ensureCounterClockwise(ring), holes: []),
            color: state.fillColor.ommColor,
            highlight: state.fillColor.ommColor
        )
        let outline = MCLineFactory.createLine(
            "circle-outline-\(state.id)",
            coordinates: closeRing(ring).map(\.ommCoord),
            style: strokeStyle(color: state.strokeColor, width: state.strokeWidth)
        )
        return OpenMobileMapsActualCircle(fills: [fill], outlines: [outline].compactMap { $0 })
    }

    override func updateCircleProperties(
        circle _: OpenMobileMapsActualCircle,
        current: CircleEntity<OpenMobileMapsActualCircle>,
        prev _: CircleEntity<OpenMobileMapsActualCircle>
    ) async -> OpenMobileMapsActualCircle? {
        await createCircle(state: current.state)
    }

    override func removeCircle(entity _: CircleEntity<OpenMobileMapsActualCircle>) async {}

    override func onPostProcess() async {
        let entities = circleManager.allEntities()
        fillLayer?.setPolygons(entities.flatMap { $0.circle?.fills ?? [] }, origin: renderOrigin)
        outlineLayer?.setLines(entities.flatMap { $0.circle?.outlines ?? [] })
    }

    func unbind() {
        fillLayer = nil
        outlineLayer = nil
    }
}

// ── 描画の共通値 ──────────────────────────────────────────────────────────

/// ポリゴンの座標の原点。
///
/// 4.0 の `setPolygons` は原点を要求する（3D 表示で精度を保つため）。平面の地図では 0 でよい。
private let renderOrigin = MCVec3D(x: 0.0, y: 0.0, z: 0.0)

// ── 線の見た目 ────────────────────────────────────────────────────────────

/// 統一の線スタイル。
///
/// 幅はポイントをピクセルへ直して `MCSizeType.screenPixel` で渡す。`mapUnit` にすると
/// 地図と一緒に太さが変わり、他プロバイダと見た目が食い違う。
@MainActor
private func strokeStyle(color: UIColor, width: Double) -> MCLineStyle {
    let colors = MCColorStateList(normal: color.ommColor, highlighted: color.ommColor)
    let gap = MCColorStateList(normal: transparentOmmColor(), highlighted: transparentOmmColor())
    return MCLineStyle(
        color: colors,
        gapColor: gap,
        opacity: Float(color.cgColor.alpha),
        blur: 0,
        widthType: .SCREEN_PIXEL,
        width: Float(width * Double(UIScreen.main.scale)),
        dashArray: [],
        dashFade: 0,
        dashAnimationSpeed: 0,
        lineCap: .ROUND,
        lineJoin: .ROUND,
        offset: 0,
        dotted: false,
        dottedSkew: 1
    )
}
