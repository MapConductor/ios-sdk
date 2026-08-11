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

// ── グラウンドイメージ ────────────────────────────────────────────────────

/// グラウンドイメージのレンダラ。
///
/// SDK の「テクスチャ付きポリゴンレイヤ」を 1 枚 1 画像として使う。タイル分割は要らない。
@MainActor
final class OpenMobileMapsGroundImageOverlayRenderer:
    AbstractGroundImageOverlayRenderer<OpenMobileMapsActualGroundImage> {
    private let layers: OpenMobileMapsLayers
    private weak var map: MCMapInterface?

    init(layers: OpenMobileMapsLayers, map: MCMapInterface?) {
        self.layers = layers
        self.map = map
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> OpenMobileMapsActualGroundImage? {
        guard let map,
              let southWest = state.bounds.southWest,
              let northEast = state.bounds.northEast,
              let layer = MCTexturedPolygonLayerInterface.create(),
              let cgImage = state.image.cgImage,
              let texture = try? TextureHolder(cgImage)
        else { return nil }

        // 4 隅は北西から時計回り。テクスチャの向きがこの順に依存する。
        let corners: [any GeoPointProtocol] = [
            GeoPoint(latitude: northEast.latitude, longitude: southWest.longitude),
            GeoPoint(latitude: northEast.latitude, longitude: northEast.longitude),
            GeoPoint(latitude: southWest.latitude, longitude: northEast.longitude),
            GeoPoint(latitude: southWest.latitude, longitude: southWest.longitude),
        ]
        layer.setPolygon(
            polygonCoord(outer: corners, holes: []),
            textureBounds: MCRectCoord(
                topLeft: MCCoord(
                    systemIdentifier: MCCoordinateSystemIdentifiers.epsg4326(),
                    x: southWest.longitude, y: northEast.latitude, z: 0.0
                ),
                bottomRight: MCCoord(
                    systemIdentifier: MCCoordinateSystemIdentifiers.epsg4326(),
                    x: northEast.longitude, y: southWest.latitude, z: 0.0
                )
            )
        )
        layer.loadTexture(texture)
        layer.setAlpha(Float(state.opacity))

        guard let layerInterface = layer.asLayerInterface() else { return nil }
        return OpenMobileMapsActualGroundImage(
            layer: layer,
            layerInterface: layers.insertBelowOverlays(layerInterface, on: map)
        )
    }

    override func updateGroundImageProperties(
        groundImage: OpenMobileMapsActualGroundImage,
        current: GroundImageEntity<OpenMobileMapsActualGroundImage>,
        prev _: GroundImageEntity<OpenMobileMapsActualGroundImage>
    ) async -> OpenMobileMapsActualGroundImage? {
        if let map { layers.remove(groundImage.layerInterface, from: map) }
        return await createGroundImage(state: current.state)
    }

    override func removeGroundImage(entity: GroundImageEntity<OpenMobileMapsActualGroundImage>) async {
        guard let map, let groundImage = entity.groundImage else { return }
        layers.remove(groundImage.layerInterface, from: map)
    }

    func unbind() { map = nil }
}

// ── ラスターレイヤ ────────────────────────────────────────────────────────

/// ラスターレイヤのレンダラ。
///
/// マーカーのタイル描画（`MarkerTileRenderer` + ローカルタイルサーバ）もこの経路を通る。
/// つまり **ここが動かないと PostOffice のような大量マーカーのページが白紙になる**。
@MainActor
final class OpenMobileMapsRasterLayerOverlayRenderer: RasterLayerOverlayRendererProtocol {
    typealias ActualLayer = OpenMobileMapsActualRasterLayer

    private let layers: OpenMobileMapsLayers
    private let loaders: [MCLoaderInterface]
    private weak var map: MCMapInterface?

    init(layers: OpenMobileMapsLayers, loaders: [MCLoaderInterface], map: MCMapInterface?) {
        self.layers = layers
        self.loaders = loaders
        self.map = map
    }

    func onAdd(data: [RasterLayerOverlayAddParams]) async -> [OpenMobileMapsActualRasterLayer?] {
        data.map { createLayer(state: $0.state) }
    }

    func onChange(
        data: [RasterLayerOverlayChangeParams<OpenMobileMapsActualRasterLayer>]
    ) async -> [OpenMobileMapsActualRasterLayer?] {
        data.map { params in
            if let map, let previous = params.current.layer {
                layers.remove(previous.layerInterface, from: map)
            }
            return createLayer(state: params.current.state)
        }
    }

    func onRemove(data: [RasterLayerEntity<OpenMobileMapsActualRasterLayer>]) async {
        guard let map else { return }
        for entity in data {
            guard let layer = entity.layer else { continue }
            layers.remove(layer.layerInterface, from: map)
        }
    }

    func onCameraChanged(mapCameraPosition _: MapCameraPosition) async {}

    func onPostProcess() async {}

    func unbind() { map = nil }

    private func createLayer(state: RasterLayerState) -> OpenMobileMapsActualRasterLayer? {
        guard state.visible, let map else { return nil }
        guard case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, scheme) = state.source else { return nil }

        let config = WebMercatorTileLayerConfig(
            layerName: state.id,
            urlTemplate: template,
            tileSize: tileSize,
            minZoomLevel: minZoom ?? 0,
            maxZoomLevel: maxZoom ?? 22,
            scheme: scheme,
            // ラスターオーバーレイは透過前提なので、粗い親レベルを重ね描きしない
            numDrawPreviousLayers: 0,
            maskTile: true
        )
        guard let layer = MCTiled2dMapRasterLayerInterface.create(config, loaders: loaders),
              let layerInterface = layer.asLayerInterface()
        else { return nil }
        layer.setAlpha(Float(state.opacity))
        return OpenMobileMapsActualRasterLayer(
            layer: layer,
            layerInterface: layers.insertBelowOverlays(layerInterface, on: map)
        )
    }
}

// ── コントローラ（どれも数行） ────────────────────────────────────────────
//
// 差分の計算も購読も当たり判定もコアの基底が持っている。ドライバーが書くのは
// 「マネージャとレンダラを繋ぐ」ことと、破棄時にレイヤの参照を切ることだけ。
//
// マネージャをコントローラ側で作ってレンダラへ渡しているのは、`onPostProcess` が
// **マネージャの全要素**を集めてレイヤへ一括で流すため。別々の実体を持たせると
// レンダラ側が空のマネージャを見て、追加したはずのオーバーレイが 1 つも描かれない。

@MainActor
final class OpenMobileMapsPolylineController:
    PolylineController<OpenMobileMapsActualPolyline, OpenMobileMapsPolylineOverlayRenderer> {
    init(lineLayer: MCLineLayerInterface?) {
        let manager = PolylineManager<OpenMobileMapsActualPolyline>()
        super.init(
            polylineManager: manager,
            renderer: OpenMobileMapsPolylineOverlayRenderer(polylineManager: manager, lineLayer: lineLayer)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

@MainActor
final class OpenMobileMapsPolygonController:
    PolygonController<OpenMobileMapsActualPolygon, OpenMobileMapsPolygonOverlayRenderer> {
    init(fillLayer: MCPolygonLayerInterface?, outlineLayer: MCLineLayerInterface?) {
        let manager = PolygonManager<OpenMobileMapsActualPolygon>()
        super.init(
            polygonManager: manager,
            renderer: OpenMobileMapsPolygonOverlayRenderer(
                polygonManager: manager,
                fillLayer: fillLayer,
                outlineLayer: outlineLayer
            )
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

@MainActor
final class OpenMobileMapsCircleController:
    CircleController<OpenMobileMapsActualCircle, OpenMobileMapsCircleOverlayRenderer> {
    init(fillLayer: MCPolygonLayerInterface?, outlineLayer: MCLineLayerInterface?) {
        let manager = CircleManager<OpenMobileMapsActualCircle>()
        super.init(
            circleManager: manager,
            renderer: OpenMobileMapsCircleOverlayRenderer(
                circleManager: manager,
                fillLayer: fillLayer,
                outlineLayer: outlineLayer
            )
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

@MainActor
final class OpenMobileMapsGroundImageController:
    GroundImageController<OpenMobileMapsActualGroundImage, OpenMobileMapsGroundImageOverlayRenderer> {
    init(layers: OpenMobileMapsLayers, map: MCMapInterface?) {
        super.init(
            groundImageManager: GroundImageManager<OpenMobileMapsActualGroundImage>(),
            renderer: OpenMobileMapsGroundImageOverlayRenderer(layers: layers, map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

@MainActor
final class OpenMobileMapsRasterLayerController:
    RasterLayerController<OpenMobileMapsActualRasterLayer, OpenMobileMapsRasterLayerOverlayRenderer> {
    init(layers: OpenMobileMapsLayers, loaders: [MCLoaderInterface], map: MCMapInterface?) {
        super.init(
            rasterLayerManager: RasterLayerManager<OpenMobileMapsActualRasterLayer>(),
            renderer: OpenMobileMapsRasterLayerOverlayRenderer(layers: layers, loaders: loaders, map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}
