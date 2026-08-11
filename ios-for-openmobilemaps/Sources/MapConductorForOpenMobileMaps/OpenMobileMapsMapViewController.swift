import CoreGraphics
import Foundation
import MapCore
import MapConductorCore
import QuartzCore
import UIKit

/// ドライバーのコントローラ（実装点 B）。**これが実装点のほぼ全部**である。
///
/// ## 書くもの
///
///  1. ``holder``               地図とビューを保持する（投影の唯一の注入点）
///  2. ``readNativeCamera()``   SDK の生カメラを ``MapCameraPosition`` へ直す
///  3. ``moveCamera(position:)`` / ``animateCamera(position:duration:)`` / ``fitBounds(bounds:padding:)``
///  4. ``installListeners()``   SDK のイベントをコアの受け口へ転送する（実装点 E）
///  5. ``declareCapabilities(into:)`` できること・できないことの宣言（実装点 H）
///
/// ## 書かなくてよいもの（コアが持っている）
///
///  - クリックのカスケード（marker → circle → groundImage → polyline → polygon → map）
///  - オーバーレイの当たり判定、`clickable = false` の透過
///  - `compositionXxx` / `updateXxx` / `hasXxx`（Capable ファサード）
///  - `visibleRegion` の組み立て
///  - `getCameraPosition()` … **足さないこと**（理由は `MapViewController.swift` の冒頭）
///
/// android-for-openmobilemaps の `OpenMobileMapsMapViewController.kt` と同じ構成。
@MainActor
public final class OpenMobileMapsMapViewController: MapViewControllerProtocol {
    public let holder: AnyMapViewHolder
    public let coroutine = CoroutineScope()
    public let overlayControllers = OverlayControllerRegistry()

    /// 型付きのホルダー。`holder` は型消去されているので、投影以外の用途はこちらを使う。
    let ommHolder: OpenMobileMapsMapViewHolder

    let layers: OpenMobileMapsLayers
    let markerController: OpenMobileMapsMarkerController
    let markerEventController: OpenMobileMapsMarkerEventController
    let polylineController: OpenMobileMapsPolylineController
    let polygonController: OpenMobileMapsPolygonController
    let circleController: OpenMobileMapsCircleController
    let groundImageController: OpenMobileMapsGroundImageController
    let rasterLayerController: OpenMobileMapsRasterLayerController

    private let loaders: [MCLoaderInterface]

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    /// 適用済みの地図デザイン。同じものを二度張らないための番人。
    private var currentDesign: (any OpenMobileMapsMapDesignTypeProtocol)?

    /// アプリが要求した tilt。
    ///
    /// SDK の 2D カメラは tilt を持たないので**読み戻せない**。要求値をここで覚えておいて
    /// ``readNativeCamera()`` に載せる（そうしないと `moveCamera(tilt: 45)` の直後に
    /// カメライベントが tilt = 0 で上書きし、Tilt ページが 1 フレームで元に戻る）。
    private var logicalTilt: Double = 0.0

    /// 前回配ったカメラ。同じ値なら配らない（``notifyCamera()`` を参照）。
    private var lastNotifiedCamera: MapCameraPosition?

    private var cameraListener: OpenMobileMapsCameraListener?

    // カメラアニメーションの状態。詳細は ``animateCamera(position:duration:)``。
    private var cameraAnimationDisplayLink: CADisplayLink?
    private var cameraAnimationFrom: MapCameraPosition?
    private var cameraAnimationTo: MapCameraPosition?
    private var cameraAnimationStartedAt: CFTimeInterval = 0
    private var cameraAnimationDurationSeconds: Double = 0

    /// レイヤ一式は外から渡す。**この地図に載せる 6 枚のレイヤは 1 か所で作って索引を
    /// 割り当てる必要がある**ため（``OpenMobileMapsLayers`` の冒頭を参照）。
    /// アプリ／ホスト側の入口は ``createOpenMobileMapsViewController(holder:loaders:serviceRegistry:)``。
    init(
        holder: OpenMobileMapsMapViewHolder,
        layers: OpenMobileMapsLayers,
        loaders: [MCLoaderInterface]
    ) {
        ommHolder = holder
        self.holder = AnyMapViewHolder(holder)
        self.layers = layers
        self.loaders = loaders

        markerController = OpenMobileMapsMarkerController(holder: holder, iconLayer: layers.iconLayer)
        markerEventController = OpenMobileMapsMarkerEventController(
            holder: holder,
            markerController: markerController
        )
        polylineController = OpenMobileMapsPolylineController(lineLayer: layers.polylineLayer)
        polygonController = OpenMobileMapsPolygonController(
            fillLayer: layers.polygonFillLayer,
            outlineLayer: layers.polygonOutlineLayer
        )
        circleController = OpenMobileMapsCircleController(
            fillLayer: layers.circleFillLayer,
            outlineLayer: layers.circleOutlineLayer
        )
        groundImageController = OpenMobileMapsGroundImageController(layers: layers, map: holder.map)
        rasterLayerController = OpenMobileMapsRasterLayerController(
            layers: layers,
            loaders: loaders,
            map: holder.map
        )

        // ★★ 忘れるとすべてが黙って効かなくなる ★★
        // compositionXxx / hasXxx / クリックカスケードは、ここに登録されたものしか見ない。
        // 「追加したのに表示されない」「タップしても無反応」の大半がこれ。
        // タイル方式マーカーはラスターレイヤとして地図へ載る。この配線が無いと
        // 大量マーカーのページ（PostOffice）が白紙になる。
        //
        // `self` はまだ初期化の途中なので、ローカルに取り出したコントローラを捕まえる。
        let rasterForMarkerTiles = rasterLayerController
        let markerTileIdPrefix = Self.markerTileIdPrefix
        markerController.rasterLayerCallback = { [weak rasterForMarkerTiles] state in
            guard let rasterForMarkerTiles else { return }
            Task { @MainActor in
                if let state {
                    await rasterForMarkerTiles.upsert(state: state)
                } else {
                    // 世代が変わると id も変わるので、前置きで拾って全部外す。
                    for entity in rasterForMarkerTiles.rasterLayerManager.allEntities()
                        where entity.state.id.hasPrefix(markerTileIdPrefix) {
                        await rasterForMarkerTiles.removeById(entity.state.id)
                    }
                }
            }
        }

        registerOverlayController(markerController)
        registerOverlayController(polylineController)
        registerOverlayController(polygonController)
        registerOverlayController(circleController)
        registerOverlayController(groundImageController)
        registerOverlayController(rasterLayerController)
    }

    // MARK: - E. SDK イベントの転送

    /// SDK のカメライベントをコアの受け口へ転送する。
    ///
    /// タップと長押しは UIKit のジェスチャ認識器から入る（``OpenMobileMapsGestures.swift``）。
    /// SDK の `MCTouchInterface` を使わないのは、ドラッグ中の**指の絶対位置**が
    /// `onMove` の差分からは復元できないため。他の iOS プロバイダも同じ形。
    func installListeners() {
        let listener = OpenMobileMapsCameraListener(controller: self)
        cameraListener = listener
        ommHolder.map.getCamera()?.addListener(listener)
        notifyMapInitialized()
    }

    /// カメラの通知。**必ず 1 フレームに 1 回へ間引くこと。**
    ///
    /// この SDK は `onVisibleBoundsChanged` を描画フレームごとに、しかも同じ値で何度も呼ぶ
    /// （android 実測: 1 秒のカメラアニメーションで **388 回**、うち大半はまったく同じ値）。
    /// 1 回ごとに ``readNativeCamera()`` を回すと、可視領域の 4 隅の逆投影がメインスレッドで
    /// 1 秒に 1,500 回以上走り、**他の地図の動きが止まる**（Camera Sync で Google Maps の
    /// アニメーションが途中で固まる形で表面化した）。
    ///
    /// 間引きは 2 段。1 段目（未処理の通知があるあいだは積まない）は
    /// ``OpenMobileMapsCameraListener`` が持ち、2 段目がここ。
    fileprivate func notifyCameraFromNativeListener() {
        let position = readNativeCamera()
        if isSameCamera(lastNotifiedCamera, position) { return }
        lastNotifiedCamera = position
        overlayControllers.dispatchCameraChanged(position)
        cameraMoveListener?(position)
    }

    private func isSameCamera(_ previous: MapCameraPosition?, _ current: MapCameraPosition) -> Bool {
        guard let last = previous else { return false }
        return last.position.latitude == current.position.latitude
            && last.position.longitude == current.position.longitude
            && last.zoom == current.zoom
            && last.bearing == current.bearing
            && last.tilt == current.tilt
    }

    /// 地図のタップ 1 か所ぶんの配線。**カスケードは書かない。**
    ///
    /// 正準の順（marker → circle → groundImage → polyline → polygon → map）は
    /// コアの `dispatchOverlayTap` が持っている。
    func handleTap(atSurfacePoint surfacePoint: CGPoint, innerPoint: CGPoint) {
        if markerEventController.handleTap(at: surfacePoint) { return }
        guard let position = ommHolder.fromInnerOffsetSync(innerPoint) else { return }
        if dispatchOverlayTap(position: position) { return }
        mapClickListener?(position)
    }

    /// 長押し。ドラッグ可能なマーカーの上ならドラッグを開始し、そうでなければ地図の長押し。
    ///
    /// - Returns: マーカーのドラッグが消費したら true。
    @discardableResult
    func handleLongPress(_ recognizer: UILongPressGestureRecognizer, in surface: UIView) -> Bool {
        if markerEventController.handleLongPress(recognizer, in: surface) { return true }
        guard recognizer.state == .began,
              let inner = ommHolder.mapView.fromSurfaceToInner(recognizer.location(in: surface)),
              let position = ommHolder.fromInnerOffsetSync(inner)
        else { return false }
        mapLongClickListener?(position)
        return false
    }

    /// ジェスチャが終わった。移動の終わりを 1 回だけ配る。
    func emitCameraMoveEndFromGesture() {
        let position = readNativeCamera()
        overlayControllers.dispatchCameraChanged(position)
        cameraMoveEndListener?(position)
    }

    // MARK: - B. カメラ

    /// SDK の生カメラを統一カメラへ直す。
    ///
    /// tilt < 0 のときは SDK に渡した中心・ズームが前進済みなので、
    /// ``OpenMobileMapsTiltEmulation/restoreLogicalCamera(center:zoom:bearing:logicalTilt:)``
    /// で論理値へ巻き戻す。
    func readNativeCamera() -> MapCameraPosition {
        readLogicalCamera().copy(visibleRegion: ommHolder.buildVisibleRegion())
    }

    /// 可視領域を載せない軽い読み取り。
    ///
    /// `buildVisibleRegion()` は 4 隅の逆投影なので、アニメーションの開始点を取るためだけに
    /// 回したくない。
    private func readLogicalCamera() -> MapCameraPosition {
        guard let camera = ommHolder.map.getCamera() else {
            return MapCameraPosition(position: GeoPoint(latitude: 0, longitude: 0, altitude: 0))
        }
        let rawCenter = ommHolder.toWgs84(camera.getCenterPosition())?.geoPoint
            ?? GeoPoint(latitude: 0, longitude: 0, altitude: 0)
        let rawZoom = Self.zoomConverter.toUnifiedZoom(camera.getZoom())
        let bearing = Self.bearingFromNativeRotation(camera.getRotation())
        let restored = OpenMobileMapsTiltEmulation.restoreLogicalCamera(
            center: rawCenter,
            zoom: rawZoom,
            bearing: bearing,
            logicalTilt: logicalTilt
        )
        return MapCameraPosition(
            position: restored.center,
            zoom: restored.zoom,
            bearing: bearing,
            tilt: logicalTilt
        )
    }

    public func moveCamera(position: MapCameraPosition) {
        cancelCameraAnimation()
        apply(position)
    }

    /// カメラを `duration` ミリ秒かけて動かす。
    ///
    /// ## SDK のアニメーションは使わない
    ///
    /// `moveToCenterPositionZoom(..., animated: true)` は**尺を指定できず、実測で常に約 300ms**
    /// で着地する。アプリが 1000ms と言っても 300ms で終わるので、他プロバイダと並べると
    /// 明らかに先に着いてしまう。フレームごとに `animated: false` の移動を繰り返し、
    /// こちらで尺を守る。
    ///
    /// 刻みは `CADisplayLink`。android は「次のフレーム時刻まで待つ」コルーチンで同じことを
    /// している（固定で 16ms 待つと、1 フレームぶんの仕事に使った時間だけ周期が伸びて
    /// 37fps まで落ちる）。iOS では表示リンクがそのまま「次のフレーム」なので、
    /// ios-for-mapkit / ios-for-maplibre と同じくこちらを使う。
    ///
    /// 補間の中身（メルカトル空間での線形補間・方位の最短回り・イージング）は
    /// ``OpenMobileMapsCameraAnimation`` にある。
    public func animateCamera(position: MapCameraPosition, duration: Long) {
        cancelCameraAnimation()
        guard duration > 0 else {
            apply(position)
            return
        }

        let from = readLogicalCamera()
        cameraMoveStartListener?(from)
        cameraAnimationFrom = from
        cameraAnimationTo = position
        cameraAnimationStartedAt = CACurrentMediaTime()
        cameraAnimationDurationSeconds = Double(duration) / 1000.0

        let displayLink = CADisplayLink(target: self, selector: #selector(onCameraAnimationTick))
        displayLink.add(to: .main, forMode: .common)
        cameraAnimationDisplayLink = displayLink
    }

    /// 走っているカメラアニメーションを止める。
    ///
    /// 新しいカメラ指示のたびに呼ぶ。**指が触れたときも呼ぶこと**
    /// （``OpenMobileMapsGestures.swift`` から）。止めないとアニメーションが
    /// ユーザーの操作と綱引きになり、地図が引き戻される。
    func cancelCameraAnimation() {
        cameraAnimationDisplayLink?.invalidate()
        cameraAnimationDisplayLink = nil
        cameraAnimationFrom = nil
        cameraAnimationTo = nil
        cameraAnimationDurationSeconds = 0
    }

    @objc private func onCameraAnimationTick() {
        guard let from = cameraAnimationFrom,
              let to = cameraAnimationTo,
              cameraAnimationDurationSeconds > 0
        else {
            cancelCameraAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - cameraAnimationStartedAt
        let progress = min(max(elapsed / cameraAnimationDurationSeconds, 0.0), 1.0)
        if progress >= 1.0 {
            // 補間の誤差を残さないよう、最後は要求された値そのものを入れる。
            cancelCameraAnimation()
            apply(to)
            return
        }
        apply(
            OpenMobileMapsCameraAnimation.interpolate(
                from: from,
                to: to,
                t: OpenMobileMapsCameraAnimation.ease(progress)
            )
        )
    }

    private func apply(_ position: MapCameraPosition) {
        logicalTilt = position.tilt
        if position.tilt != ommHolder.mapView.visualTilt {
            ommHolder.mapView.visualTilt = position.tilt
            // 傾きが変わったらアイコンの縦の引き伸ばしを付け直す。
            // 詳細は OpenMobileMapsMarkerOverlayRenderer.onVisualTiltChanged()。
            markerController.renderer.onVisualTiltChanged()
        }

        let shifted = OpenMobileMapsTiltEmulation.shiftedCamera(position)
        guard let camera = ommHolder.map.getCamera() else { return }
        camera.move(
            toCenterPositionZoom: shifted.center.ommCoord,
            zoom: Self.zoomConverter.toNativeZoom(shifted.zoom),
            animated: false
        )
        // 方位が変わっていないなら触らない。毎フレーム呼ぶと SDK 側で無駄な
        // 行列の作り直しが走る。
        let rotation = Self.nativeRotationFromBearing(position.bearing)
        if abs(camera.getRotation() - rotation) > Self.rotationEpsilon {
            camera.setRotation(rotation, animated: false)
        }
    }

    public func fitBounds(bounds: GeoRectBounds, padding: Int) {
        // GeoRectBounds の 4 隅は optional。空の矩形を渡されうる。
        guard let southWest = bounds.southWest,
              let northEast = bounds.northEast,
              let camera = ommHolder.map.getCamera(),
              let viewportWidth = ommHolder.viewportSizePx()?.width
        else { return }

        // SDK は余白を「ビューポートに対する割合」で受け取る。
        let paddingPc = viewportWidth > 0
            ? Float(min(max(Double(padding) / Double(viewportWidth), 0.0), 0.4))
            : 0

        camera.move(
            toBoundingBox: MCRectCoord(
                topLeft: MCCoord(
                    systemIdentifier: MCCoordinateSystemIdentifiers.epsg4326(),
                    x: southWest.longitude,
                    y: northEast.latitude,
                    z: 0
                ),
                bottomRight: MCCoord(
                    systemIdentifier: MCCoordinateSystemIdentifiers.epsg4326(),
                    x: northEast.longitude,
                    y: southWest.latitude,
                    z: 0
                )
            ),
            paddingPc: paddingPc,
            animated: false,
            minZoom: nil,
            maxZoom: nil
        )
    }

    public func applyUISettings(_ settings: MapUISettings) {
        ommHolder.map.getCamera()?.setRotationEnabled(settings.rotateGesture)
    }

    // MARK: - C. 地図デザイン

    public func setMapDesignType(_ value: any OpenMobileMapsMapDesignTypeProtocol) {
        if currentDesign?.getValue() == value.getValue() { return }
        currentDesign = value
        let config = WebMercatorTileLayerConfig(
            layerName: "design-\(value.id)",
            urlTemplate: value.tileUrlTemplate,
            tileSize: value.tileSize
        )
        let layer = MCTiled2dMapRasterLayerInterface.create(config, loaders: loaders)
        layers.setDesignLayer(layer?.asLayerInterface(), on: ommHolder.map)
    }

    // MARK: - H. capability の宣言

    /// このドライバーで何ができて何ができないかを宣言する。
    ///
    /// **「宣言しない」＝「使えない」ではない**（Unknown）。書く価値があるのは
    /// 「**できない**と分かっているもの」で、宣言しておくと該当機能が黙って無反応になる
    /// 代わりに理由つきのログが 1 回出る。
    public func declareCapabilities(into registry: MutableMapServiceRegistry) {
        OpenMobileMapsCapabilities.declare(into: registry)
    }

    /// 最初のカメラを 1 回配る。
    ///
    /// ビューポートの大きさが決まる前に配ると `visibleRegion` が組めないので、
    /// レイアウトが済んでから呼ぶこと。
    func sendInitialCameraUpdate() {
        notifyMapInitialized()
        guard ommHolder.viewportSizePx() != nil else { return }
        let position = readNativeCamera()
        overlayControllers.dispatchCameraChanged(position)
        cameraMoveListener?(position)
    }

    // MARK: - 後始末

    public func clearOverlays() async {
        await markerController.clear()
        await polylineController.clear()
        await polygonController.clear()
        await circleController.clear()
        await groundImageController.clear()
        await rasterLayerController.clear()
        layers.clearAll()
    }

    public func destroy() {
        cancelCameraAnimation()
        if let cameraListener {
            ommHolder.map.getCamera()?.removeListener(cameraListener)
        }
        cameraListener = nil
        markerEventController.unbind()
        markerController.unbind()
        polylineController.unbind()
        polygonController.unbind()
        circleController.unbind()
        groundImageController.unbind()
        rasterLayerController.unbind()
        overlayControllers.destroyAll()
    }

    // MARK: - リスナー

    public func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    public func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    public func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    public func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    public func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    public func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }

    func notifyMapInitialized() { mapInitializedListener?(InitState.MapLoaded) }

    // MARK: - 定数

    /// ズームの往復換算。
    ///
    /// この SDK のズームは 2 の指数ではなく**縮尺の分母**なので、コアの
    /// `WebMercatorZoomAltitudeConverter` のオフセット方式では変換できない
    /// （``OpenMobileMapsZoomAltitudeConverter`` のコメントを参照）。
    static let zoomConverter = OpenMobileMapsZoomAltitudeConverter()

    /// これ未満の方位差では `setRotation` を呼ばない（度）。
    private static let rotationEpsilon: Float = 0.01

    /// マーカータイルのラスターレイヤ id の前置き。外すときの目印。
    static let markerTileIdPrefix = "marker-tile-"

    /// 方位の符号。**SDK は MapConductor と逆回りである。**
    ///
    /// MapConductor の bearing は Google 準拠で「カメラが向いている方位を北から時計回りに測る」。
    /// SDK の `setRotation` は地図を反時計回りに回す量なので、符号を反転する。
    /// 反転を忘れると bearing 270 の地図が 90 として描かれ、**ちょうど 180 度ずれる**
    /// （単独で見ると「回っている」ので正しく見えてしまう。android では Tilt ページを
    /// MapLibre と並べて気づいた）。
    static func nativeRotationFromBearing(_ bearing: Double) -> Float { Float(-bearing) }

    /// SDK の回転角 → MapConductor の bearing（0 以上 360 未満）。
    static func bearingFromNativeRotation(_ rotation: Float) -> Double {
        let bearing = Double(-rotation).truncatingRemainder(dividingBy: 360.0)
        return bearing < 0 ? bearing + 360.0 : bearing
    }
}

/// SDK のカメライベントの受け口。
///
/// ## 1 段目の間引きをここでやる理由
///
/// このコールバックは**描画スレッド**から来る。到着のたびにメインスレッドへ仕事を積むと、
/// 積むこと自体が渋滞の原因になる（`notifyCameraFromNativeListener` のコメントを参照）。
/// 未処理のものがあるあいだは積まない、という判定を到着した側で済ませる。
///
/// android の `AtomicBoolean` に相当する。Swift には同じものが無いので `NSLock` で守る。
private final class OpenMobileMapsCameraListener: NSObject, MCMapCameraListenerInterface {
    private let pendingLock = NSLock()
    private var pending = false

    /// **weak で持つこと。** カメラ（＝地図）がこのリスナーを強参照しているので、
    /// ここを強参照にするとコントローラが地図と一緒に生き残り、地図を閉じても解放されない。
    private weak var controller: OpenMobileMapsMapViewController?

    init(controller: OpenMobileMapsMapViewController) {
        self.controller = controller
        super.init()
    }

    func onVisibleBoundsChanged(_: MCRectCoord, zoom _: Double) { schedule() }

    func onRotationChanged(_: Float) { schedule() }

    func onMapInteraction() {}

    func onCameraChange(
        _: [NSNumber],
        projectionMatrix _: [NSNumber],
        origin _: MCVec3D,
        verticalFov _: Float,
        horizontalFov _: Float,
        width _: Float,
        height _: Float,
        focusPointAltitude _: Float,
        focusPointPosition _: MCCoord,
        zoom _: Float
    ) {}

    private func schedule() {
        pendingLock.lock()
        if pending {
            pendingLock.unlock()
            return
        }
        pending = true
        pendingLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingLock.lock()
            self.pending = false
            self.pendingLock.unlock()
            MainActor.assumeIsolated {
                self.controller?.notifyCameraFromNativeListener()
            }
        }
    }
}
