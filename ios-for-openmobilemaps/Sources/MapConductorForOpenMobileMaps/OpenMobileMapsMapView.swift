import Foundation
import MapCore
import MapConductorCore
import SwiftUI
import UIKit

/// 地図の SwiftUI 入口（実装点 G）。
///
/// ```swift
/// OpenMobileMapsMapView(state: state) {
///     Polyline(state: routeState)
///     Circle(state: circleState)
/// }
/// ```
///
/// ## この SDK に固有の手順
///
/// android では `MapsCore.initialize()` と `MapView.registerLifecycle()` の 2 つが必須で、
/// 後者を忘れると**地図が真っ黒のまま**エラーも出ない。**iOS ではどちらも要らない。**
/// `MCMapView` は `MTKView` の派生で、`init` の中で `mapInterface.resume()` まで済ませ、
/// 自分の描画ループで回るため。ネイティブライブラリの読み込みも SwiftPM が解決する。
public struct OpenMobileMapsMapView: View {
    @ObservedObject private var state: OpenMobileMapsViewState

    private let handlers: MapViewHandlers<OpenMobileMapsViewState>
    private let cameraRestriction: CameraRestriction?
    private let content: () -> MapViewContent

    public init(
        state: OpenMobileMapsViewState,
        cameraRestriction: CameraRestriction? = nil,
        onMapLoaded: OnMapLoadedHandler<OpenMobileMapsViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onMapLongClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        handlers = MapViewHandlers(
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize
        )
        self.cameraRestriction = cameraRestriction
        self.content = content
    }

    public var body: some View {
        // プロバイダのレジストリが見えるのは content を組み立てているあいだだけ
        // （Compose が content ラムダの周りで `LocalMapServiceRegistry` を提供するのと同じ窓）。
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return MapViewBase(
            // この SDK は出典表示を自前で描かない。ここを渡さないと
            // **タイルの利用条件を満たさない状態**で表示される（OpenMobileMapsDesign を参照）。
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: mapContent
        ) {
            OpenMobileMapsMapViewRepresentable(
                state: state,
                cameraRestriction: cameraRestriction,
                handlers: handlers,
                content: mapContent
            )
        }
    }
}

private struct OpenMobileMapsMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: OpenMobileMapsViewState
    let cameraRestriction: CameraRestriction?
    let handlers: MapViewHandlers<OpenMobileMapsViewState>
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, handlers: handlers)
    }

    func makeUIView(context: Context) -> OpenMobileMapsMapSurface {
        if let sdkInitialize = handlers.sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }

        let surface = OpenMobileMapsMapSurface(frame: .zero)
        // 地図は EPSG:3857 で構成する（タイルがすべて 3857 で、ズームの縮尺の導出も
        // 「地図単位 = メルカトルメートル」を前提にしているため）。
        //
        // 密度は **160 x scale** を渡すこと。既定は `MCDisplayMetrics.pixelsPerInch`
        // （実測の物理 dpi）だが、それだと端末ごとに縮尺が数 % ずれ、Google Maps と
        // 大きさが揃わない。`OpenMobileMapsZoomAltitudeConverter.scaleAtZoom0` の導出も
        // この密度を前提にしている。android で `densityDpi` を渡しているのと同じ理由。
        let mapView = MCMapView(
            mapConfig: MCMapConfig(mapCoordinateSystem: MCCoordinateSystemFactory.getEpsg3857System()),
            pixelsPerInch: Float(160.0 * UIScreen.main.scale),
            is3D: false
        )
        surface.attach(mapView: mapView)

        context.coordinator.bind(state: state, surface: surface)
        context.coordinator.applyCameraRestriction(cameraRestriction)
        context.coordinator.updateContent(content)
        return surface
    }

    func updateUIView(_ uiView: OpenMobileMapsMapSurface, context: Context) {
        _ = uiView
        // 地図デザインとジェスチャはここで反映する。`setMapDesignType` は同じデザインなら
        // 何もしないので、毎フレーム呼んでもタイルレイヤは張り替わらない。
        context.coordinator.applyMapDesignType(state.mapDesignType)
        context.coordinator.applyUISettings(state.uiSettings)
        context.coordinator.applyCameraRestriction(cameraRestriction)
        context.coordinator.updateContent(content)
    }

    static func dismantleUIView(_: OpenMobileMapsMapSurface, coordinator: Coordinator) {
        coordinator.unbind()
    }

    /// 地図の寿命を持つ。
    ///
    /// MapTiler / MapLibre のコーディネータより短いのは、**オーバーレイコントローラを
    /// コントローラ側が作っている**ため（この SDK はレイヤを 1 か所で作って索引を
    /// 割り当てる必要があり、その置き場がコントローラになる）。ここは
    /// 「コレクタに繋ぐ」「ジェスチャを繋ぐ」だけになる。
    @MainActor
    final class Coordinator: MapViewCoordinatorBase<OpenMobileMapsViewState> {
        private weak var surface: OpenMobileMapsMapSurface?
        private var controller: OpenMobileMapsMapViewController?
        private var overlayScope: MapOverlayScope?
        private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?

        func bind(state: OpenMobileMapsViewState, surface: OpenMobileMapsMapSurface) {
            guard let mapView = surface.mapView else { return }
            self.surface = surface

            let holder = OpenMobileMapsMapViewHolder(mapView: surface, map: mapView.mapInterface)
            let controller = createOpenMobileMapsViewController(
                holder: holder,
                // 素の `MCTextureLoader` ではなく派生を使うこと。マーカータイルの
                // 空タイル（404）をそのまま渡すと、粗い親タイルが透けて残る。
                loaders: [OpenMobileMapsTileLoader()],
                serviceRegistry: state.serviceRegistry
            )
            self.controller = controller

            state.setMapViewHolder(holder)
            // 拡張モジュール（ヒートマップ等）がオーバーレイコントローラを登録できるようにする。
            state.serviceRegistry.put(OverlayControllerRegistryKey.self, controller.overlayControllers)

            controller.setMapDesignType(state.mapDesignType)
            controller.installListeners()

            // SDK のカメラ変更 → state へ push。アプリは state を読む（pull させない）。
            controller.setCameraMoveStartListener { [weak self, weak state] position in
                state?.updateCameraPosition(position)
                self?.onCameraMoveStart?(position)
            }
            controller.setCameraMoveListener { [weak self, weak state] position in
                state?.updateCameraPosition(position)
                // ★ 吹き出しは画面空間に置いてあるので、地図が動いたら**こちらで置き直す**。
                //   忘れると吹き出しがその場に取り残される。しかも起動直後は地図の大きさが
                //   決まる前に一度置かれるため、置き直しが無いと**そのままずれた位置に
                //   居座る**（実機で「吹き出しが 1 つだけ画面端に出る」形で出た）。
                self?.infoBubbleCoordinator?.updateAllLayouts()
                self?.onCameraMove?(position)
            }
            controller.setCameraMoveEndListener { [weak self, weak state] position in
                state?.updateCameraPosition(position)
                self?.infoBubbleCoordinator?.updateAllLayouts()
                self?.onCameraMoveEnd?(position)
            }
            controller.setMapClickListener { [weak self] point in self?.onMapClick?(point) }
            controller.setMapLongClickListener { [weak self] point in self?.onMapLongClick?(point) }

            // 状態を集めるのはコレクタ。コントローラは購読も差分も持たない。
            let overlayScope = MapOverlayScope()
            self.overlayScope = overlayScope
            bindOverlayCollector(overlayScope.markerCollector, to: controller.markerController)
            bindOverlayCollector(overlayScope.polylineCollector, to: controller.polylineController)
            bindOverlayCollector(overlayScope.polygonCollector, to: controller.polygonController)
            bindOverlayCollector(overlayScope.circleCollector, to: controller.circleController)
            bindOverlayCollector(overlayScope.groundImageCollector, to: controller.groundImageController)
            bindOverlayCollector(overlayScope.rasterLayerCollector, to: controller.rasterLayerController)

            attachGestures(to: surface)
            attachInfoBubbleContainer(to: surface)
            // 入れ物の大きさは入れ物側に面倒をみてもらう（理由は `overlayContainer` を参照）。
            surface.overlayContainer = infoBubbleContainer
            attachScreenSpaceOverlays(holder: holder, controller: controller)

            // state が持っている初期カメラをここで適用する。
            state.setController(controller)
            applyUISettings(state.uiSettings)

            // 最初のカメラは**レイアウトが済んでから**配る。ビューポートの大きさが
            // 決まる前だと `visibleRegion` が組めず、可視領域を見るページが空になる。
            DispatchQueue.main.async { [weak self] in
                self?.controller?.sendInitialCameraUpdate()
                self?.performMapLoadedOnce { self?.onMapLoaded?(state) }
            }
        }

        /// 画面空間のオーバーレイ（吹き出し・マーカーアニメーション）を繋ぐ。
        ///
        /// 投影は**必ずホルダーを通す**こと。ホルダーは内側の `MCMapView` の座標を
        /// 入れ物の座標へ畳んで返すので、傾けているときも SwiftUI 側と位置が揃う
        /// （`OpenMobileMapsMapSurface.fromInnerToSurface` を参照）。
        private func attachScreenSpaceOverlays(
            holder: OpenMobileMapsMapViewHolder,
            controller: OpenMobileMapsMapViewController
        ) {
            let bubbles = InfoBubbleOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak holder] point in holder?.toScreenOffset(position: point) },
                projectionGate: screenProjectionGate(feature: "InfoBubble"),
                resolveMarkerStateForIcon: { [weak controller] id, bubbleMarker in
                    controller?.markerController.getMarkerState(for: id) ?? bubbleMarker
                },
                iconMetrics: { markerState in
                    let icon = (markerState.icon ?? DefaultMarkerIcon()).toBitmapIcon()
                    return MarkerIconMetrics(size: icon.size, anchor: icon.anchor, infoAnchor: icon.infoAnchor)
                }
            )
            infoBubbleCoordinator = bubbles
            controller.markerController.onUpdateInfoBubble = { [weak bubbles] id in
                bubbles?.updateInfoBubblePosition(for: id)
            }

            // マーカーのアニメーションは画面空間のレイヤで演じる。吹き出しと同じ入れ物を
            // 共有し、その下に入る。地図と一緒に寝ないので、傾けていても正しく見える。
            controller.markerController.renderer.animationOverlay = MarkerAnimationOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak holder] point in holder?.toScreenOffset(position: point) },
                projectionGate: screenProjectionGate(feature: "marker animation overlay")
            )
        }

        func applyCameraRestriction(_ restriction: CameraRestriction?) {
            applyCameraRestriction(restriction, to: controller)
        }

        func applyUISettings(_ settings: MapUISettings) {
            controller?.applyUISettings(settings)
        }

        func applyMapDesignType(_ design: any OpenMobileMapsMapDesignTypeProtocol) {
            controller?.setMapDesignType(design)
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleCoordinator?.syncInfoBubbles(content.infoBubbles)
            controller?.markerController.tilingOptions = content.markerTilingOptions
            overlayScope?.markerCollector.sync(content.markers.map(\.state))
            overlayScope?.polylineCollector.sync(content.polylines.map(\.state))
            overlayScope?.polygonCollector.sync(content.polygons.map(\.state))
            overlayScope?.circleCollector.sync(content.circles.map(\.state))
            overlayScope?.groundImageCollector.sync(content.groundImages.map(\.state))
            overlayScope?.rasterLayerCollector.sync(content.rasterLayers.map(\.state))
            infoBubbleCoordinator?.updateAllLayouts()
        }

        func unbind() {
            // 登録した capability を取り下げる。レジストリの持ち主は state で、ビューより
            // 長生きするため、ここで外さないと破棄済みのコントローラを掴んだまま残る。
            state.serviceRegistry.removeProviderRegistrations()
            controller?.destroy()
            state.setController(nil)
            state.setMapViewHolder(nil)
            controller = nil
            infoBubbleCoordinator?.unbind()
            infoBubbleCoordinator = nil
            overlayScope?.clear()
            overlayScope = nil
            surface = nil
        }

        // MARK: - E. ジェスチャ

        /// タップと長押しを繋ぐ。
        ///
        /// ## SDK の `MCTouchInterface` を使わない理由
        ///
        /// android では `SimpleTouchInterface` でタップ・長押しを受けている。iOS でも同じ
        /// protocol はあるが、こちらは他の 9 プロバイダと同じく UIKit のジェスチャ認識器を使う。
        /// コアの `DefaultMarkerEventController` が `UIGestureRecognizer.State` に対応した
        /// 状態遷移で書かれており（ドラッグ中の**指の絶対位置**が要る。SDK の `onMove` は
        /// 差分しか渡してこない）、iOS ではそちらに合わせるのが素直なため。
        ///
        /// `MCMapView` 自身のタッチ転送は `cancelsTouchesInView = false` の認識器なので、
        /// こちらを足しても地図の操作は妨げない。
        private func attachGestures(to surface: OpenMobileMapsMapSurface) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            surface.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.2
            longPress.cancelsTouchesInView = false
            surface.addGestureRecognizer(longPress)

            // 指が触れたらカメラアニメーションを止める。止めないと自前の
            // アニメーションがユーザーの操作と綱引きになり、地図が引き戻される。
            let touchDown = OpenMobileMapsTouchDownGestureRecognizer(
                target: self,
                action: #selector(handleTouchDown(_:))
            )
            surface.addGestureRecognizer(touchDown)
        }

        /// SDK の投影は**内側の `MCMapView` の座標系**で動くので、入れ物で受けた点を
        /// そこへ畳んでから渡す（`OpenMobileMapsMapViewHolder.fromInnerOffsetSync` を参照）。
        private func innerPoint(of recognizer: UIGestureRecognizer) -> CGPoint? {
            guard let surface, let mapView = surface.mapView else { return nil }
            return surface.convert(recognizer.location(in: surface), to: mapView)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let surface, let inner = innerPoint(of: recognizer) else { return }
            controller?.handleTap(atSurfacePoint: recognizer.location(in: surface), innerPoint: inner)
            infoBubbleCoordinator?.updateAllLayouts()
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let surface else { return }
            controller?.handleLongPress(recognizer, in: surface)
            infoBubbleCoordinator?.updateAllLayouts()
        }

        @objc private func handleTouchDown(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                controller?.cancelCameraAnimation()
            case .ended, .cancelled:
                controller?.emitCameraMoveEndFromGesture()
            default:
                break
            }
        }
    }
}

/// 「指が触れた／離れた」だけを知るための認識器。
///
/// 何も消費せず（`cancelsTouchesInView = false`、常に他と同時認識）、状態だけを配る。
/// カメラアニメーションの打ち切りと、`onCameraMoveEnd` の発火に使う。
private final class OpenMobileMapsTouchDownGestureRecognizer: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .began
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func canBePrevented(by _: UIGestureRecognizer) -> Bool { false }

    override func canPrevent(_: UIGestureRecognizer) -> Bool { false }
}

/// 命令的なコントローラ一式を組み立てる。
///
/// SwiftUI からも、React Native のような非 SwiftUI ホストからも同じものを使えるように
/// ここに置く。android-for-openmobilemaps の `createOpenMobileMapsViewController` に対応する。
@MainActor
public func createOpenMobileMapsViewController(
    holder: OpenMobileMapsMapViewHolder,
    loaders: [MCLoaderInterface],
    serviceRegistry: MutableMapServiceRegistry? = nil
) -> OpenMobileMapsMapViewController {
    let layers = OpenMobileMapsLayers()
    layers.attach(to: holder.map)

    let controller = OpenMobileMapsMapViewController(holder: holder, layers: layers, loaders: loaders)
    if let serviceRegistry {
        controller.declareCapabilities(into: serviceRegistry)
    }
    return controller
}
