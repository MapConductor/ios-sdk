import Foundation
import MapConductorCore
import UIKit

/// SwiftUI を通さないホスト（React Native の `reactnative-for-template`）から
/// 同じ地図を使うための入口。
///
/// `TemplateMapCoordinator`（SwiftUI の `Coordinator` にあたるもの）と**同じ配線**を、
/// SwiftUI に依存しない形で持つ。実際のドライバーでは `MapLibreMapHost` /
/// `HereMapHost` / `GoogleMapHost` がこれに当たる。
///
/// `@_spi(MapConductorDriver)` を付けること。`scripts/api-surface.sh` は
/// `.swiftinterface` を見るので、SPI はアプリ向けの凍結 API に載らない。
/// 使う側は `@_spi(MapConductorDriver) import MapConductorForTemplate` と書く。
@MainActor
@_spi(MapConductorDriver)
public final class TemplateMapHost {
    private let map = TemplateMap()
    private let overlayScope = MapOverlayScope()
    private weak var state: TemplateViewState?

    public private(set) var controller: TemplateMapViewController?

    public init() {}

    /// 地図のビューを作って返す。
    ///
    /// **雛形の地図は描画面を持たない**（`TemplateMap` はディスプレイリストだけを持ち、
    /// SwiftUI 側も `Color.clear` を置いているだけ）。本物のドライバーはここで
    /// SDK の `MKMapView` / `MLNMapView` などを返す。
    public func makeMapView(state: TemplateViewState, content: MapViewContent) -> UIView {
        let view = UIView(frame: .zero)
        attach(state: state)
        updateContent(content)
        return view
    }

    private func attach(state: TemplateViewState) {
        let controller = TemplateMapViewController(map: map)
        self.controller = controller
        self.state = state

        state.setMapViewHolder(TemplateViewHolder(map: map))
        state.setController(controller)

        // 状態を集めるのはコレクタ。コントローラは購読も差分も持たない。
        bindOverlayCollector(overlayScope.circleCollector, to: controller.circleController)
        bindOverlayCollector(overlayScope.polylineCollector, to: controller.polylineController)
        bindOverlayCollector(overlayScope.polygonCollector, to: controller.polygonController)
        bindOverlayCollector(overlayScope.groundImageCollector, to: controller.groundImageController)
        bindOverlayCollector(overlayScope.rasterLayerCollector, to: controller.rasterLayerController)

        controller.declareCapabilities(into: state.serviceRegistry)

        // SDK のカメラ変更 → state へ push。アプリは state を読む（pull させない）。
        controller.setCameraMoveEndListener { [weak state] position in
            state?.updateCameraPosition(position)
        }

        controller.notifyMapInitialized()
    }

    /// アプリが宣言したオーバーレイをコレクタへ流す。**差分はコレクタが取る。**
    public func updateContent(_ content: MapViewContent) {
        overlayScope.circleCollector.sync(content.circles.map(\.state))
        overlayScope.polylineCollector.sync(content.polylines.map(\.state))
        overlayScope.polygonCollector.sync(content.polygons.map(\.state))
        overlayScope.groundImageCollector.sync(content.groundImages.map(\.state))
        overlayScope.rasterLayerCollector.sync(content.rasterLayers.map(\.state))
        guard let controller else { return }
        Task { await controller.markerController.add(data: content.markers.map(\.state)) }
    }

    public func unbind() {
        controller?.destroy()
        state?.setController(nil)
        state?.setMapViewHolder(nil)
        controller = nil
    }
}
