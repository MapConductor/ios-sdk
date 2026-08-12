import CoreGraphics
import Foundation
import MapCore
import MapConductorCore
import UIKit

/// 実装点 E / F。SDK のタッチをコアの受け口へつなぐ。
///
/// ## ここだけ他の iOS プロバイダと形が違う
///
/// 他の 9 プロバイダは UIKit のジェスチャ認識器（`UITapGestureRecognizer` など）を
/// 地図ビューに足してタップを受けている。**この SDK ではそれが動かない。**
///
/// `MCMapView` は `TouchForwardingGestureRecognizer` という連続ジェスチャを自分に付けており、
/// その `shouldBeRequiredToFail(by:)` が**画面左端 44pt より内側で始まったタッチについて
/// 常に true を返す**（`maps-core/ios/maps/MCMapView.swift`）。つまり「こちらの認識器が
/// 認識するには、まず SDK 側の認識器が失敗しなければならない」という依存が張られる。
/// ところが SDK 側の認識器は `touchesBegan` で `.began` に入り `touchesEnded` で `.ended` に
/// 至るだけで**決して失敗しない**ので、こちらのタップ・長押しは**一度も発火しない**。
///
/// UIKit の `shouldRecognizeSimultaneouslyWith` や `shouldRequireFailureOf` を
/// true / false にしても解けない。失敗依存は「どちらか一方が true を返せば成立し、
/// false を返しても解除は保証されない」という規則だからである
/// （実機で 64 回タップして 0 回しか届かないことを計測して確かめた）。
///
/// したがって **android と同じく SDK 自身のタッチ経路（``MCTouchInterface``）を使う**。
/// android-for-openmobilemaps の `OpenMobileMapsTouchListener` と同じ構成で、
/// あちらの `SimpleTouchInterface`（既定実装つき基底）が iOS には無いぶん、
/// 使わないメソッドも並べて false を返している。
///
/// ## 呼ばれるスレッドが 2 種類ある
///
/// - `onTouchDown` / `onMove` / `onMoveComplete` … `touchesBegan` などから**同期で**来る（メイン）
/// - `onClickConfirmed` / `onLongPress` … SDK が押下時間を測るために遅延タスクへ積むので
///   **描画スレッド**から来る（`DefaultTouchHandler::checkState`）
///
/// どちらから来ても構わないよう、コントローラへの用事はすべてメインへ回す。
/// **戻り値だけは同期で返さなければならない**（消費するかどうかを SDK がその場で見る）ので、
/// ドラッグ中かどうかは ``NSLock`` で守った旗をこちら側に持つ。
final class OpenMobileMapsTouchListener: NSObject, MCTouchInterface {
    /// **weak で持つこと。** タッチハンドラ（＝地図）がこのリスナーを強参照するので、
    /// ここを強参照にするとコントローラが地図と一緒に生き残る。
    private weak var controller: OpenMobileMapsMapViewController?

    private let lock = NSLock()

    /// マーカーをつかんでいるか。`onMove` を消費するかどうかの判断に使う（実装点 F）。
    private var isDraggingMarker = false

    /// ドラッグ中の指の位置（内側ビューの物理ピクセル）。
    ///
    /// **`onMove` は差分しか渡してこない。** 長押しの位置を起点に差分を足し込んで
    /// 絶対位置を組み直す。SDK 側も同じ足し込みで `touchPosition` を持っているので、
    /// これで指の位置と 1 ピクセルもずれない。
    private var dragPoint: CGPoint = .zero

    init(controller: OpenMobileMapsMapViewController) {
        self.controller = controller
        super.init()
    }

    // MARK: - 使うもの

    /// 指が触れた。カメラアニメーションを止める。
    ///
    /// 止めないと ``OpenMobileMapsMapViewController/animateCamera(position:duration:)`` が
    /// 刻むフレームとユーザーの操作が綱引きになり、パンしても引き戻される。
    /// **消費はしない**（false）ので、SDK 側の通常の操作はそのまま流れる。
    func onTouchDown(_: MCVec2F) -> Bool {
        onMain { $0.cancelCameraAnimation() }
        return false
    }

    /// タップが確定した。カスケード（marker → circle → groundImage → polyline → polygon → map）は
    /// コアが回すので、ここは座標を渡すだけ。
    func onClickConfirmed(_ posScreen: MCVec2F) -> Bool {
        let point = posScreen.cgPoint
        onMain { $0.handleTap(atInnerPixelPoint: point) }
        return true
    }

    /// 長押し。ドラッグ可能なマーカーの上ならドラッグを始め、そうでなければ地図の長押し。
    func onLongPress(_ posScreen: MCVec2F) -> Bool {
        let point = posScreen.cgPoint
        lock.lock()
        dragPoint = point
        lock.unlock()

        onMain { [weak self] controller in
            let started = controller.handleLongPress(atInnerPixelPoint: point)
            self?.setDraggingMarker(started)
        }
        return true
    }

    /// 指が動いた。
    ///
    /// マーカーをつかんでいるあいだは **true を返して消費する**。リスナーは
    /// 「先に登録されたものが true を返したらそこで打ち切り」なので、これが
    /// 実装点 F（ドラッグ中のパン抑止）になる。`MCMapCameraInterface` には
    /// 「パンだけ止める」API が無いため、ここで止めるのが唯一の手段
    /// （``OpenMobileMapsCapabilities`` で `gestureScroll` を非対応と宣言してあるのはそのため）。
    func onMove(_ deltaScreen: MCVec2F, confirmed _: Bool, doubleClick _: Bool) -> Bool {
        lock.lock()
        guard isDraggingMarker else {
            lock.unlock()
            return false
        }
        dragPoint = CGPoint(x: dragPoint.x + CGFloat(deltaScreen.x), y: dragPoint.y + CGFloat(deltaScreen.y))
        let point = dragPoint
        lock.unlock()

        onMain { $0.handleDrag(state: .changed, atInnerPixelPoint: point) }
        return true
    }

    /// 指が離れた。
    ///
    /// ドラッグしていたならそれを確定させ、していなければカメラの移動終了を配る。
    func onMoveComplete() -> Bool {
        lock.lock()
        let wasDragging = isDraggingMarker
        let point = dragPoint
        isDraggingMarker = false
        lock.unlock()

        guard wasDragging else {
            onMain { $0.emitCameraMoveEndFromGesture() }
            return false
        }
        onMain { $0.handleDrag(state: .ended, atInnerPixelPoint: point) }
        return true
    }

    /// タッチが取り消された。つかんだままのドラッグを畳む。
    ///
    /// **ここを空にしないこと。** 電話の着信などでタッチが消えたとき、
    /// コアが覚えている「掴む前の `isScrollEnabled`」が戻らないまま残る。
    func clearTouch() {
        lock.lock()
        let wasDragging = isDraggingMarker
        let point = dragPoint
        isDraggingMarker = false
        lock.unlock()

        guard wasDragging else { return }
        onMain { $0.handleDrag(state: .cancelled, atInnerPixelPoint: point) }
    }

    // MARK: - 使わないもの（android の SimpleTouchInterface の既定に相当）

    func onClickUnconfirmed(_: MCVec2F) -> Bool { false }

    func onDoubleClick(_: MCVec2F) -> Bool { false }

    func onHover(_: MCVec2F) -> Bool { false }

    func onHoverComplete() -> Bool { false }

    func onOneFingerDoubleClickMoveComplete() -> Bool { false }

    func onTwoFingerClick(_: MCVec2F, posScreen2 _: MCVec2F) -> Bool { false }

    func onTwoFingerMove(_: [MCVec2F], posScreenNew _: [MCVec2F]) -> Bool { false }

    func onTwoFingerMoveComplete() -> Bool { false }

    func onScroll(_: MCVec2F, scrollDelta _: Float) -> Bool { false }

    // MARK: - 補助

    private func setDraggingMarker(_ value: Bool) {
        lock.lock()
        isDraggingMarker = value
        lock.unlock()
    }

    /// コントローラへの用事をメインへ回す。
    ///
    /// 描画スレッドから来る経路（`onClickConfirmed` / `onLongPress`）があるので、
    /// 呼び先が `@MainActor` である以上ここを通さないと成立しない。
    private func onMain(_ body: @escaping @MainActor (OpenMobileMapsMapViewController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard let controller = self.controller else { return }
                body(controller)
            }
        }
    }
}

private extension MCVec2F {
    /// SDK の画面座標は**内側ビューの物理ピクセル**。ポイントへの換算は受け側で行う
    /// （``OpenMobileMapsMapViewController/innerPoint(fromPixelPoint:)``）。
    var cgPoint: CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
}

// MARK: - コントローラ側の受け口

extension OpenMobileMapsMapViewController {
    /// 地図のタップ 1 か所ぶんの配線。**カスケードは書かない。**
    ///
    /// 正準の順（marker → circle → groundImage → polyline → polygon → map）は
    /// コアの `dispatchOverlayTap` が持っている。
    func handleTap(atInnerPixelPoint pixelPoint: CGPoint) {
        let inner = innerPoint(fromPixelPoint: pixelPoint)
        if markerEventController.handleTap(at: ommHolder.mapView.fromInnerToSurface(inner)) { return }
        // クラスタリング等の strategy 描画マーカーは通常の markerController に居ないので、
        // ここで別に引き当てる（googlemaps 等の strategy フォールバックと同じ役割）。
        if handleStrategyTap(at: ommHolder.mapView.fromInnerToSurface(inner)) { return }
        guard let position = ommHolder.fromInnerOffsetSync(inner) else { return }
        if dispatchOverlayTap(position: position) { return }
        emitMapClick(position)
    }

    /// strategy 側マーカーの当たり判定と配送。重なっているときはアンカーが近いほうを選ぶ。
    private func handleStrategyTap(at point: CGPoint) -> Bool {
        guard let strategyController = strategyManager.controller else { return false }
        let defaultIcon = DefaultMarkerIcon()
        var bestState: MarkerState?
        var bestDistance = CGFloat.infinity
        for entity in strategyController.markerManager.allEntities() where entity.state.clickable {
            guard let screen = ommHolder.toScreenOffset(position: entity.state.position) else { continue }
            guard MarkerHitTest.hitsIcon(
                touchScreen: point,
                markerScreen: screen,
                state: entity.state,
                defaultIcon: defaultIcon
            ) else { continue }
            let distance = hypot(point.x - screen.x, point.y - screen.y)
            if distance < bestDistance {
                bestDistance = distance
                bestState = entity.state
            }
        }
        guard let state = bestState else { return false }
        strategyController.dispatchClick(state)
        return true
    }

    /// 長押し。マーカーのドラッグが始まったら true。
    func handleLongPress(atInnerPixelPoint pixelPoint: CGPoint) -> Bool {
        let inner = innerPoint(fromPixelPoint: pixelPoint)
        if markerEventController.handleLongPress(
            state: .began,
            at: ommHolder.mapView.fromInnerToSurface(inner)
        ) {
            return true
        }
        guard let position = ommHolder.fromInnerOffsetSync(inner) else { return false }
        emitMapLongClick(position)
        return false
    }

    /// ドラッグの続き。開始（`.began`）だけは ``handleLongPress(atInnerPixelPoint:)`` が受ける。
    func handleDrag(state: MarkerDragGestureState, atInnerPixelPoint pixelPoint: CGPoint) {
        let inner = innerPoint(fromPixelPoint: pixelPoint)
        _ = markerEventController.handleLongPress(
            state: state,
            at: ommHolder.mapView.fromInnerToSurface(inner)
        )
    }

    /// SDK の画面座標（物理ピクセル）→ 内側ビューのポイント。
    ///
    /// 換算を忘れると 3 倍の端末で 3 倍の位置を叩くことになる。詳細は
    /// ``OpenMobileMapsMapViewHolder`` の冒頭。
    private func innerPoint(fromPixelPoint pixelPoint: CGPoint) -> CGPoint {
        let scale = ommHolder.mapView.renderScale
        guard scale > 0 else { return pixelPoint }
        return CGPoint(x: pixelPoint.x / scale, y: pixelPoint.y / scale)
    }
}
