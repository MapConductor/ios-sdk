import CoreGraphics
import Foundation
import MapConductorCore

// ============================================================================
// D. レンダラ 6 種 × onAdd / onChange / onRemove / onPostProcess（実装点 25）
// ============================================================================
//
// **ここがドライバーの本体。**「MapConductor の状態」→「SDK のオブジェクト」の
// 翻訳だけを書く。差分計算・購読・順序・重複排除はすべてコアが済ませてある。
//
// 各レンダラは 3 つの関数だけ実装すればよい:
//   createXxx(state:)                 … 状態から SDK オブジェクトを作る
//   updateXxxProperties(_:current:prev:) … 変わったところだけ SDK へ反映する
//   removeXxx(entity:)                … SDK から外す
//
// **当たり判定は書かない。**コアの Manager が持っている（測地線ポリゴンの巻き数
// 判定、穴の除外、球面距離、線分への近接）。書くと二重になってずれる。

// MARK: - 円

@MainActor
final class TemplateCircleRenderer: AbstractCircleOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createCircle(state: CircleState) async -> TemplateShape? {
        // 実際の SDK ではここで SDK の円を作る。
        // 円の輪郭が要る SDK は、コアの `circleToRing` を使うこと（測地線・
        // ±180 分割・リングの閉じ方まで面倒を見てくれる）。
        map?.add(id: state.id, kind: .circle, points: [GeoPoint.from(position: state.center)])
    }

    override func updateCircleProperties(
        circle: TemplateShape,
        current: CircleEntity<TemplateShape>,
        prev: CircleEntity<TemplateShape>
    ) async -> TemplateShape? {
        // `current.fingerPrint` と `prev.fingerPrint` を比べて、変わったところだけ触る。
        // 中心や半径が変わったなら作り直しでよい。
        if current.fingerPrint.center != prev.fingerPrint.center {
            circle.points = [GeoPoint.from(position: current.state.center)]
        }
        return circle
    }

    override func removeCircle(entity: CircleEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

/// コントローラは**この 3 つ**だけ書く。差分も購読も持たない
/// （`bindOverlayCollector` が `add(data:)` / `update(state:)` を流してくる）。
@MainActor
final class TemplateCircleController: CircleController<TemplateShape, TemplateCircleRenderer> {
    init(map: TemplateMap?) {
        super.init(circleManager: CircleManager<TemplateShape>(), renderer: TemplateCircleRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ポリライン

@MainActor
final class TemplatePolylineRenderer: AbstractPolylineOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> TemplateShape? {
        map?.add(id: state.id, kind: .polyline, points: state.points.map { GeoPoint.from(position: $0) })
    }

    override func updatePolylineProperties(
        polyline: TemplateShape,
        current: PolylineEntity<TemplateShape>,
        prev _: PolylineEntity<TemplateShape>
    ) async -> TemplateShape? {
        polyline.points = current.state.points.map { GeoPoint.from(position: $0) }
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplatePolylineController: PolylineController<TemplateShape, TemplatePolylineRenderer> {
    init(map: TemplateMap?) {
        super.init(polylineManager: PolylineManager<TemplateShape>(), renderer: TemplatePolylineRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ポリゴン

@MainActor
final class TemplatePolygonRenderer: AbstractPolygonOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> TemplateShape? {
        // 穴（`state.holes`）を持てない SDK は、
        //  - 穴を無視する            → capability を `degraded` で宣言する
        //  - 外周を分割して穴を避ける → capability を `approximated` で宣言する
        // どちらでもよいが、**黙って無視しない**こと。
        map?.add(id: state.id, kind: .polygon, points: state.points.map { GeoPoint.from(position: $0) })
    }

    override func updatePolygonProperties(
        polygon: TemplateShape,
        current: PolygonEntity<TemplateShape>,
        prev _: PolygonEntity<TemplateShape>
    ) async -> TemplateShape? {
        polygon.points = current.state.points.map { GeoPoint.from(position: $0) }
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplatePolygonController: PolygonController<TemplateShape, TemplatePolygonRenderer> {
    init(map: TemplateMap?) {
        super.init(polygonManager: PolygonManager<TemplateShape>(), renderer: TemplatePolygonRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - 地上画像

@MainActor
final class TemplateGroundImageRenderer: AbstractGroundImageOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> TemplateShape? {
        map?.add(
            id: state.id,
            kind: .groundImage,
            points: [state.bounds.southWest, state.bounds.northEast].compactMap { $0 }
        )
    }

    override func updateGroundImageProperties(
        groundImage: TemplateShape,
        current _: GroundImageEntity<TemplateShape>,
        prev _: GroundImageEntity<TemplateShape>
    ) async -> TemplateShape? {
        groundImage
    }

    override func removeGroundImage(entity: GroundImageEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplateGroundImageController: GroundImageController<TemplateShape, TemplateGroundImageRenderer> {
    init(map: TemplateMap?) {
        super.init(
            groundImageManager: GroundImageManager<TemplateShape>(),
            renderer: TemplateGroundImageRenderer(map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - ラスターレイヤ

@MainActor
final class TemplateRasterLayerRenderer: AbstractRasterLayerOverlayRenderer<TemplateShape> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> TemplateShape? {
        // ここを実装すると heatmap / geojson-layer / タイル方式マーカーが
        // まとめて動くようになる（どれもラスタータイルの重ね合わせで実装されている）。
        map?.add(id: state.id, kind: .rasterLayer, points: [])
    }

    override func updateLayerProperties(
        layer: TemplateShape,
        current _: RasterLayerEntity<TemplateShape>,
        prev _: RasterLayerEntity<TemplateShape>
    ) async -> TemplateShape? {
        layer
    }

    override func removeLayer(entity: RasterLayerEntity<TemplateShape>) async {
        map?.remove(id: entity.state.id)
    }

    func unbind() { map = nil }
}

@MainActor
final class TemplateRasterLayerController: RasterLayerController<TemplateShape, TemplateRasterLayerRenderer> {
    init(map: TemplateMap?) {
        super.init(
            rasterLayerManager: RasterLayerManager<TemplateShape>(),
            renderer: TemplateRasterLayerRenderer(map: map)
        )
    }

    func unbind() {
        renderer.unbind()
        destroy()
    }
}

// MARK: - マーカー

@MainActor
final class TemplateMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = TemplateShape

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    private weak var map: TemplateMap?

    init(map: TemplateMap?) { self.map = map }

    /// `bitmapIcon` は**コアが用意した最終的なアイコン**。既定アイコンの合成も
    /// ラベル描画も済んでいる。SDK のアノテーションに載せるだけでよい。
    func onAdd(data: [MarkerOverlayAddParams]) async -> [TemplateShape?] {
        data.map { params in
            map?.add(id: params.state.id, kind: .marker, points: [GeoPoint.from(position: params.state.position)])
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<TemplateShape>]) async -> [TemplateShape?] {
        data.map { params in
            let marker = params.current.marker
            marker?.points = [GeoPoint.from(position: params.current.state.position)]
            return marker
        }
    }

    func onRemove(data: [MarkerEntity<TemplateShape>]) async {
        data.forEach { map?.remove(id: $0.state.id) }
    }

    /// アニメーションを持たない SDK は空のままでよい。
    /// ただし `animateStartListener` / `animateEndListener` を呼ばないなら、
    /// `markerAnimation` capability を `unsupported` で宣言すること。
    func onAnimate(entity _: MarkerEntity<TemplateShape>) async {}

    func onPostProcess() async {}

    func unbind() { map = nil }
}

/// マーカーの当たり判定・ドラッグ・アニメの保持はすべてコアの
/// ``AbstractMarkerController`` と ``DefaultMarkerEventController`` が持つ。
@MainActor
final class TemplateMarkerController: AbstractMarkerController<TemplateShape, TemplateMarkerRenderer> {
    private weak var map: TemplateMap?

    init(map: TemplateMap?) {
        self.map = map
        super.init(markerManager: MarkerManager<TemplateShape>(), renderer: TemplateMarkerRenderer(map: map))
    }

    func unbind() {
        renderer.unbind()
        map = nil
        destroy()
    }
}
