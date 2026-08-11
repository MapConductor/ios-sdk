import Foundation
import MapCore
import UIKit

/// SDK の `MCMapView` を載せる入れ物。**傾きの見た目だけ**を受け持つ。
///
/// ios-for-arcgis の 2D と同じ構造。平面地図のカメラはピッチを持てないため、ビューそのものを
/// X 軸まわりに回して遠近感を作る（react-for-leaflet の CSS `rotateX` と同じ方式）。
/// 地図側の中心・縮尺の付け替えは ``OpenMobileMapsTiltEmulation`` が受け持ち、
/// ここは描画だけを扱う。
///
/// 負の tilt は中心の前進で表現されるので、描画角度は常に `abs(tilt)` を使う。
///
/// ## 投影はここで畳む
///
/// SDK の投影は内側の `MCMapView` の座標系で返るので、傾けているあいだは拡大・回転のぶんだけ
/// SwiftUI 側（InfoBubble・マーカーアニメーション）とずれる。``fromInnerToSurface(_:)`` /
/// ``fromSurfaceToInner(_:)`` を必ず通すこと。
///
/// ## 直せていないこと
///
/// マーカーは内側の `MCMapView` が描くので、この回転で**一緒に寝る**（本来は常に正面を
/// 向くべき）。ビューを回す方式である以上ここでは避けられない。ios-for-arcgis の 2D も同じ。
public final class OpenMobileMapsMapSurface: UIView {
    /// 回した平面が元のフレームを覆うための拡大率。ArcGIS2D / leaflet / openlayers と同じ 200%。
    private static let planeScale: CGFloat = 2.0

    /// 正射影に近づけるための視点距離 ÷ ビューサイズ。大きいほど遠近が弱い。
    private static let orthographicDistanceFactor: CGFloat = 200.0

    public private(set) var mapView: MCMapView?

    /// 見た目を傾ける角度（論理 tilt、度）。
    public var visualTilt: Double = 0.0 {
        didSet {
            guard visualTilt != oldValue else { return }
            applyVisualTilt()
        }
    }

    /// 画面空間のオーバーレイ（吹き出し・マーカーアニメーション）の入れ物。
    ///
    /// **大きさをここで面倒みること。** コアの `attachInfoBubbleContainer(to:)` は
    /// 呼ばれた時点の `bounds` を入れて `autoresizingMask` に任せるが、`makeUIView` の
    /// 時点ではこのビューはまだ大きさ 0 で、**0 からの比例拡大は 0 のまま**になる。
    /// するとコアの `updateAllLayouts()` が `container.bounds.isEmpty` で丸ごと
    /// 早期 return し、**吹き出しが 1 つも出ない**（実機で踏んだ）。
    public weak var overlayContainer: UIView? {
        didSet { overlayContainer?.frame = bounds }
    }

    public func attach(mapView: MCMapView) {
        guard self.mapView !== mapView else { return }
        self.mapView?.removeFromSuperview()
        self.mapView = mapView
        // 変形を使うので autoresizing / AutoLayout には任せず、フレームを自分で置く。
        mapView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(mapView)
        setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        applyVisualTilt()
        overlayContainer?.frame = bounds
    }

    /// SDK の画面座標（物理ピクセル）と UIKit のポイントの比。詳細は
    /// ``OpenMobileMapsMapViewHolder`` の投影のコメントを参照。
    var renderScale: CGFloat { mapView?.contentScaleFactor ?? UIScreen.main.scale }

    /// 回した平面が元のフレームを覆うよう ``planeScale`` 倍に広げてから回し、親でクリップする。
    ///
    /// 拡大しても縮尺は変わらない（縮尺は解像度で決まる）ので、単に地図が広く映る
    /// ＝傾いたカメラがより広い地表を見るのと同じになる。
    private func applyVisualTilt() {
        guard let mapView, bounds.width > 0, bounds.height > 0 else { return }

        let angle = min(max(abs(visualTilt), 0.0), OpenMobileMapsTiltEmulation.maxTiltDegrees)
        let scale = angle > 0 ? Self.planeScale : 1.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        // 変形の影響を受けないよう、フレームは変形を外してから置く。
        mapView.layer.transform = CATransform3DIdentity
        mapView.frame = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        // 遠近は弱く掛ける（ほぼ正射影）。react-for-leaflet / react-for-openlayers の CSS も
        // perspective を置いておらず、planeScale = 1 / cos(60°) がちょうど効く前提。
        var transform = CATransform3DIdentity
        if angle > 0 {
            let distance = max(size.width, size.height) * Self.orthographicDistanceFactor
            transform.m34 = -1.0 / distance
            transform = CATransform3DRotate(transform, CGFloat(angle) * .pi / 180.0, 1, 0, 0)
        }
        mapView.layer.transform = transform
        clipsToBounds = true
    }

    /// 内側の `MCMapView` の座標 → この入れ物の座標。
    ///
    /// ## これを通さないとオーバーレイが全部ずれる
    ///
    /// SDK の投影は**内側の `MCMapView` の座標系**で返る。傾けているとき内側は
    /// ``planeScale`` 倍に広げて中央寄せしてあるので、そのまま SwiftUI 側
    /// （InfoBubble・マーカーアニメーション）へ渡すと、拡大と中央寄せのぶんだけずれる。
    /// android では tilt 45 度のページで **InfoBubble が画面外へ飛ぶ**という形で出た。
    ///
    /// `UIView.convert(_:to:)` は `layer.transform` による射影も含むので、遠近ぶんも
    /// 正しく畳める。tilt = 0 のときは恒等変換なので、何も変わらない。
    public func fromInnerToSurface(_ point: CGPoint) -> CGPoint {
        guard let mapView else { return point }
        return mapView.convert(point, to: self)
    }

    /// この入れ物の座標 → 内側の `MCMapView` の座標。``fromInnerToSurface(_:)`` の逆。
    public func fromSurfaceToInner(_ point: CGPoint) -> CGPoint? {
        guard let mapView else { return point }
        return convert(point, to: mapView)
    }
}
