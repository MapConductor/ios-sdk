import CoreGraphics
import Foundation
import MapConductorCore

// ============================================================================
// B. コントローラ（実装点 5）+ E. イベント転送（実装点 6）+ H. capability（実装点 1）
// ============================================================================

/// 実装点 B。
///
/// ## 書くもの
///
///  - `holder`（投影の注入点）
///  - `readNativeCamera()`（SDK のカメラ → ``MapCameraPosition``）
///  - `moveCamera` / `animateCamera` / `fitBounds`
///
/// ## 書かないもの
///
///  - `visibleRegion` … `holder.buildVisibleRegion()` が 4 隅を逆投影して組む
///  - クリックのカスケード … `dispatchOverlayTap(position:)` を呼ぶだけ
///  - Capable ファサードの 28 メソッド … `registerOverlayController` するだけ
///  - `getCameraPosition()` … **足さないこと**（理由は `MapViewController.swift` の冒頭）
@MainActor
public final class TemplateMapViewController: MapViewControllerProtocol {
    public let holder: AnyMapViewHolder
    public let coroutine = CoroutineScope()
    public let overlayControllers = OverlayControllerRegistry()

    private let map: TemplateMap
    private let templateHolder: TemplateViewHolder

    let circleController: TemplateCircleController
    let polylineController: TemplatePolylineController
    let polygonController: TemplatePolygonController
    let groundImageController: TemplateGroundImageController
    let rasterLayerController: TemplateRasterLayerController
    let markerController: TemplateMarkerController

    /// マーカーのタップ／ドラッグ。状態遷移はコアが持つ。
    let markerEventController: DefaultMarkerEventController

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    /// 統一ズーム（Google 準拠）と SDK の生ズームの相互変換。
    ///
    /// SDK のズームが Google と同じ体系なら `zoomOffset: 0`。
    /// タイル 512px 系（Mapbox など）は `zoomOffset: 1`。
    /// **較正値をコアに固定しないこと。**同じ SDK でもプラットフォームで違う値になる
    /// （ArcGIS の zoom0Altitude は iOS だけ別の実測値になっている）。
    let zoomConverter = WebMercatorZoomAltitudeConverter(zoomOffset: 0)

    public init(map: TemplateMap) {
        self.map = map
        let holder = TemplateViewHolder(map: map)
        self.templateHolder = holder
        self.holder = AnyMapViewHolder(holder)

        circleController = TemplateCircleController(map: map)
        polylineController = TemplatePolylineController(map: map)
        polygonController = TemplatePolygonController(map: map)
        groundImageController = TemplateGroundImageController(map: map)
        rasterLayerController = TemplateRasterLayerController(map: map)
        markerController = TemplateMarkerController(map: map)
        markerEventController = DefaultMarkerEventController(
            surface: TemplateMarkerDragSurface(map: map),
            host: TemplateMarkerEventHost(markerController: markerController)
        )

        // ★★ 忘れるとすべてが黙って効かなくなる ★★
        // compositionXxx / hasXxx / クリックカスケードは、ここに登録されたものしか見ない。
        // 「追加したのに表示されない」「タップしても無反応」の大半がこれ。
        // MapDriverConformance.checkOverlaySlots() で機械的に捕まえられる。
        registerOverlayController(markerController)
        registerOverlayController(circleController)
        registerOverlayController(groundImageController)
        registerOverlayController(polylineController)
        registerOverlayController(polygonController)
        registerOverlayController(rasterLayerController)

        installListeners()
    }

    // MARK: - E. SDK イベントの転送（各 1 行）

    private func installListeners() {
        map.onCameraChanged = { [weak self] in
            guard let self else { return }
            let position = self.readNativeCamera()
            self.cameraMoveListener?(position)
            self.cameraMoveEndListener?(position)
        }
        map.onTap = { [weak self] point in self?.handleTap(at: point) }
        map.onLongPress = { [weak self] point in self?.handleLongPress(at: point) }
    }

    /// タップ 1 か所ぶんの配線。**カスケードは書かない。**
    ///
    /// 正準の順（marker → circle → groundImage → polyline → polygon → map）は
    /// `dispatchMarkerTap` と `dispatchOverlayTap` が持っている。
    private func handleTap(at point: CGPoint) {
        if markerEventController.handleTap(at: point) { return }
        guard let position = map.geoPoint(at: point) else { return }
        if dispatchOverlayTap(position: position) { return }
        mapClickListener?(position)
    }

    private func handleLongPress(at point: CGPoint) {
        if markerEventController.handleLongPress(state: .began, at: point) { return }
        guard let position = map.geoPoint(at: point) else { return }
        mapLongClickListener?(position)
    }

    // MARK: - B. カメラ

    /// SDK のカメラ → ``MapCameraPosition``。**生ズームを統一ズームへ直すのを忘れない。**
    /// ここがずれると、当たり判定の許容量が実際の縮尺と食い違い、
    /// 「線や円をタップしても反応しない」という形で表面化する。
    func readNativeCamera() -> MapCameraPosition {
        MapCameraPosition(
            position: map.center,
            zoom: zoomConverter.toUnifiedZoom(map.zoom, latitude: map.center.latitude),
            bearing: map.bearingDegrees,
            tilt: map.tiltDegrees,
            visibleRegion: templateHolder.buildVisibleRegion()
        )
    }

    public func moveCamera(position: MapCameraPosition) {
        apply(position)
        map.onCameraChanged?()
    }

    public func animateCamera(position: MapCameraPosition, duration _: Long) {
        // アニメーション API を持たない SDK は即時反映でよい。
        // その場合は cameraAnimation capability を degraded で宣言すること。
        cameraMoveStartListener?(readNativeCamera())
        apply(position)
        map.onCameraChanged?()
    }

    public func fitBounds(bounds: GeoRectBounds, padding _: Int) {
        // GeoRectBounds の 4 隅は optional。空の矩形を渡されうる。
        guard let southWest = bounds.southWest, let northEast = bounds.northEast else { return }
        map.center = GeoPoint(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2,
            altitude: 0
        )
        map.onCameraChanged?()
    }

    private func apply(_ position: MapCameraPosition) {
        map.center = GeoPoint.from(position: position.position)
        map.zoom = zoomConverter.toNativeZoom(position.zoom, latitude: position.position.latitude)
        map.bearingDegrees = position.bearing
        map.tiltDegrees = position.tilt
    }

    // MARK: - H. capability の宣言（実装点 1）

    /// 実装点 H。**Unknown と Unsupported を混同しないこと。**
    ///
    /// 宣言が無い（`unknown`）は「まだ宣言していない」であって「使えない」ではない。
    /// `unsupported` にすると**コアが動いている機能を止める**。
    /// 別経路で動いているなら `degraded` / `approximated` にすること。
    func declareCapabilities(into registry: MutableMapServiceRegistry) {
        // 代役の投影は bearing / tilt を見ていないので、回転・傾斜させるとずれる。
        // 「動くが正確ではない」= approximated。unsupported ではない。
        registry.declare(.cameraRotate, .approximated("投影が bearing を見ていないため位置がずれる"))
        registry.declare(.cameraTilt, .approximated("投影が tilt を見ていないため位置がずれる"))
        // 動かないものだけ unsupported にする。**理由を必ず書く**
        // （書かないと診断ログがアプリ開発者に何も伝えない）。
        registry.declare(.markerDrag, .unsupported("代役の SDK はネイティブのマーカー引き当てを持たない"))
    }

    // MARK: - 後始末

    public func clearOverlays() async {
        await circleController.clear()
        await polylineController.clear()
        await polygonController.clear()
        await groundImageController.clear()
        await rasterLayerController.clear()
        await markerController.clear()
    }

    public func destroy() {
        markerEventController.unbind()
        circleController.unbind()
        polylineController.unbind()
        polygonController.unbind()
        groundImageController.unbind()
        rasterLayerController.unbind()
        markerController.unbind()
        overlayControllers.destroyAll()
    }

    public func applyUISettings(_ settings: MapUISettings) {
        map.isScrollEnabled = settings.scrollGesture
    }

    // MARK: - リスナー

    public func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    public func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    public func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    public func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    public func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    public func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func notifyMapInitialized() { mapInitializedListener?(InitState.MapLoaded) }
}

/// ``TemplateMarkerController`` をコアの ``MarkerEventHostProtocol`` へ橋渡しする。
///
/// **`markerController` は weak で持つこと。**コントローラ側が
/// イベントコントローラを強参照しているので、ここを強参照にすると循環する。
@MainActor
private final class TemplateMarkerEventHost: MarkerEventHostProtocol {
    private weak var markerController: TemplateMarkerController?

    init(markerController: TemplateMarkerController) { self.markerController = markerController }

    func markerId(atScreenPoint _: CGPoint) -> String? {
        // 実際のドライバーは SDK のヒットテスト（描画済みシンボルの引き当て）を呼ぶ。
        nil
    }

    func markerState(for id: String) -> MarkerState? {
        markerController?.markerManager.getEntity(id)?.state
    }

    func handleTiledMarkerTap(atScreenPoint _: CGPoint) -> Bool { false }

    func dispatchClick(state: MarkerState) { markerController?.dispatchClick(state: state) }
    func dispatchDragStart(state: MarkerState) { markerController?.dispatchDragStart(state: state) }
    func dispatchDrag(state: MarkerState) { markerController?.dispatchDrag(state: state) }
    func dispatchDragEnd(state: MarkerState) { markerController?.dispatchDragEnd(state: state) }
    func onUpdateInfoBubble(_: String) {}
}
