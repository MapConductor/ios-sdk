import CoreGraphics
import Foundation
import MapCore
import MapConductorCore

/// 実装点 A。**投影をここ以外に書かないこと。**
///
/// Open Mobile Maps は `MCMapCameraInterface` に
/// `screenPosFromCoord` / `coordFromScreenPosition` の**同期変換を両方向持っている**ので、
/// InfoBubble・タイル方式マーカーの当たり判定・マーカーアニメ・`buildVisibleRegion` が
/// すべてそのまま動く（ios-for-longdo のように同期変換が無い SDK ではここが nil になる）。
///
/// ## 単位は「物理ピクセル」であってポイントではない
///
/// **ここが一番踏みやすい。** `MCMapView` はビューポートに `drawableSize`（＝ピクセル）を
/// 渡し、タッチも `contentScaleFactor` を掛けてから SDK へ流している。つまり SDK の画面座標は
/// **物理ピクセル**で、UIKit のポイントとは端末の倍率ぶん食い違う。
///
/// 換算を忘れても**地図・マーカー・オーバーレイは正しく描かれる**（すべて SDK が描くので
/// 一貫している）。ずれるのはこの投影を使う側、つまり **InfoBubble・マーカーアニメーション・
/// 当たり判定・`visibleRegion`** だけ。実機では「吹き出しがマーカーから離れた場所に出る」
/// という形で出た（3 倍の端末で 3 倍の位置へ飛ぶ）。
///
/// ## 座標系の変換方向に注意
///
/// 地図は EPSG:3857（Web メルカトル、単位はメートル）で構成してある。タイルがどれも 3857 なのと、
/// ``OpenMobileMapsZoomAltitudeConverter`` の縮尺の導出が「地図単位 = メルカトルメートル」を
/// 前提にしているため。
///
/// - **入力**（``toScreenOffset(position:)``）: EPSG:4326 の `MCCoord` をそのまま渡してよい。
///   SDK が `MCCoordinateConversionHelperInterface` で地図の系へ変換する。
/// - **出力**（``fromScreenOffsetSync(offset:)``）: SDK は**地図の系（3857）**で返す。
///   ここで 4326 へ戻さないと、緯度経度のつもりでメートル値を扱うことになる。
///   症状は「タップ位置が地球の裏側になる」で、非常に分かりやすく壊れる。
@MainActor
public final class OpenMobileMapsMapViewHolder: MapViewHolderProtocol {
    public let mapView: OpenMobileMapsMapSurface
    public let map: MCMapInterface

    init(mapView: OpenMobileMapsMapSurface, map: MCMapInterface) {
        self.mapView = mapView
        self.map = map
    }

    /// 地理座標 → 画面座標。
    ///
    /// SDK が返すのは**内側の `MCMapView` の座標**なので、
    /// ``OpenMobileMapsMapSurface/fromInnerToSurface(_:)`` で入れ物の座標へ畳んでから返すこと。
    /// 傾けているとき内側は拡大・回転しているため、畳まないとオーバーレイが全部ずれる。
    public func toScreenOffset(position: any GeoPointProtocol) -> CGPoint? {
        guard let camera = map.getCamera() else { return nil }
        let screen = camera.screenPos(from: position.ommCoord)
        let scale = mapView.renderScale
        let inner = CGPoint(x: CGFloat(screen.x) / scale, y: CGFloat(screen.y) / scale)
        guard inner.x.isFinite, inner.y.isFinite else { return nil }
        return mapView.fromInnerToSurface(inner)
    }

    /// 画面座標 → 地理座標。入り口で入れ物の座標を内側の座標へ戻す（``toScreenOffset(position:)`` の逆）。
    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        guard let inner = mapView.fromSurfaceToInner(offset) else { return nil }
        return fromInnerOffsetSync(inner)
    }

    /// **内側の `MCMapView` の座標** → 地理座標。
    ///
    /// ## タッチ経路は必ずこちらを使うこと
    ///
    /// SDK のタッチハンドラは内側の `MCMapView` に付くので、届く座標はすでに内側の座標系である。
    /// そこへ ``fromScreenOffsetSync(offset:)``（入れ物の座標を受け取る想定）を使うと、
    /// 内側への逆変換が**二重に**掛かる。
    ///
    /// tilt = 0 では変換が恒等なので気づけない。android では PostOffice ページの InfoBubble を
    /// タップすると `tilt = 30` でズームインする仕様で、**その直後からマーカーがタップに
    /// 反応しなくなる**という形で発覚した。
    func fromInnerOffsetSync(_ offset: CGPoint) -> GeoPoint? {
        guard let camera = map.getCamera() else { return nil }
        let scale = mapView.renderScale
        let coord = camera.coord(
            fromScreenPosition: MCVec2F(x: Float(offset.x * scale), y: Float(offset.y * scale))
        )
        guard let wgs84 = toWgs84(coord) else { return nil }
        return wgs84.geoPoint
    }

    /*
     * ビューポートの大きさはコアの既定実装（`mapView as? UIView` の bounds）が解決する。
     *
     * 返るのは入れ物（``OpenMobileMapsMapSurface``）の大きさ。投影も入れ物の座標系へ
     * 畳んであるので、傾けていても `visibleRegion` の 4 隅は実際に見えている範囲になる。
     */

    /// 地図の座標系（EPSG:3857）→ EPSG:4326。
    func toWgs84(_ coord: MCCoord) -> MCCoord? {
        if coord.systemIdentifier == MCCoordinateSystemIdentifiers.epsg4326() { return coord }
        guard let helper = map.getCoordinateConverterHelper() else { return nil }
        return helper.convert(MCCoordinateSystemIdentifiers.epsg4326(), coordinate: coord)
    }
}
