import CoreGraphics
import Foundation
import MapConductorCore

// ============================================================================
// A. あなたが使う地図 SDK の代役
// ============================================================================
//
// ここだけを実際の SDK に置き換える。まわり（ホルダー・コントローラ・レンダラ）の
// **形はそのまま**使える。
//
// 代役なので描画はしない。カメラと投影と「置かれた図形」を覚えるだけ。
// それでも投影の往復・カメラの往復・オーバーレイの追加削除は本物と同じ手順で
// 動くので、適合スイートは意味のあるチェックになる。

/// 地図に置かれた図形 1 つ。実際の SDK では `MLNPolygon` や `MKCircle` にあたる。
public final class TemplateShape {
    public let id: String
    public let kind: OverlayKind
    public var points: [GeoPoint]

    init(id: String, kind: OverlayKind, points: [GeoPoint]) {
        self.id = id
        self.kind = kind
        self.points = points
    }
}

/// 地図 SDK の代役。
public final class TemplateMap {
    /// カメラ。実際の SDK では `mapView.camera` にあたる。
    public var center: GeoPoint = GeoPoint(latitude: 0, longitude: 0, altitude: 0)
    public var zoom: Double = 2
    public var bearingDegrees: Double = 0
    public var tiltDegrees: Double = 0

    /// ビューポート。実際の SDK では `mapView.bounds.size`。
    public var sizePx: CGSize = CGSize(width: 375, height: 667)

    /// パンできるか。ドラッグ中だけ切る（``MarkerDragSurface`` が読み書きする）。
    public var isScrollEnabled: Bool = true

    public private(set) var shapes: [String: TemplateShape] = [:]

    /// SDK 側のイベント。ドライバーはこれをコアの受け口へ転送する（実装点 E）。
    public var onCameraChanged: (() -> Void)?
    public var onTap: ((CGPoint) -> Void)?
    public var onLongPress: ((CGPoint) -> Void)?

    public init() {}

    // MARK: - オーバーレイ

    @discardableResult
    public func add(id: String, kind: OverlayKind, points: [GeoPoint]) -> TemplateShape {
        let shape = TemplateShape(id: id, kind: kind, points: points)
        shapes[id] = shape
        return shape
    }

    public func remove(id: String) { shapes.removeValue(forKey: id) }

    public func removeAll() { shapes.removeAll() }

    // MARK: - 投影（実装点 A の本体）

    /// 地理座標 → 画面座標。
    ///
    /// 代役なので素の Web メルカトルで計算する。**bearing と tilt は無視している**ので、
    /// 回転・傾斜させた状態では位置がずれる。だから
    /// ``TemplateMapViewController/declareCapabilities()`` で `cameraRotate` /
    /// `cameraTilt` を `approximated` として宣言している（`unsupported` ではない）。
    public func screenPoint(for position: GeoPointProtocol) -> CGPoint? {
        let world = Self.worldPoint(latitude: position.latitude, longitude: position.longitude, zoom: zoom)
        let origin = Self.worldPoint(latitude: center.latitude, longitude: center.longitude, zoom: zoom)
        return CGPoint(
            x: world.x - origin.x + sizePx.width / 2,
            y: world.y - origin.y + sizePx.height / 2
        )
    }

    /// 画面座標 → 地理座標。``screenPoint(for:)`` の逆。
    public func geoPoint(at point: CGPoint) -> GeoPoint? {
        let origin = Self.worldPoint(latitude: center.latitude, longitude: center.longitude, zoom: zoom)
        let world = CGPoint(
            x: origin.x + point.x - sizePx.width / 2,
            y: origin.y + point.y - sizePx.height / 2
        )
        return Self.geoPoint(world: world, zoom: zoom)
    }

    private static let tileSize: Double = 256

    private static func worldSize(zoom: Double) -> Double { tileSize * pow(2.0, zoom) }

    private static func worldPoint(latitude: Double, longitude: Double, zoom: Double) -> CGPoint {
        let size = worldSize(zoom: zoom)
        // 極は Web メルカトルで無限大になるのでクランプする。地図 SDK はどれも同じことをしている。
        let clampedLatitude = min(max(latitude, -85.051_128_78), 85.051_128_78)
        let latitudeRad = clampedLatitude * .pi / 180
        let x = (longitude + 180) / 360 * size
        let y = (1 - log(tan(latitudeRad) + 1 / cos(latitudeRad)) / .pi) / 2 * size
        return CGPoint(x: x, y: y)
    }

    private static func geoPoint(world: CGPoint, zoom: Double) -> GeoPoint {
        let size = worldSize(zoom: zoom)
        let longitude = Double(world.x) / size * 360 - 180
        let n = Double.pi - 2 * .pi * Double(world.y) / size
        let latitude = 180 / Double.pi * atan(0.5 * (exp(n) - exp(-n)))
        return GeoPoint(latitude: latitude, longitude: longitude, altitude: 0)
    }
}

// ============================================================================
// A. ホルダー — 投影の唯一の注入点（実装点 4 つ）
// ============================================================================

/// 実装点 A。**投影をここ以外に書かないこと。**
///
/// コアの InfoBubble・タイル方式マーカーの当たり判定・マーカーアニメ・
/// `buildVisibleRegion` は、すべてここを通して画面座標を得る。
/// プロバイダ側に `convert(_:toCoordinateFrom:)` を撒くと、同じ変換が
/// 1 プロバイダに 3〜4 か所できて必ずずれる（移行前がそうだった）。
///
/// 同期変換が用意できない SDK（WebView ブリッジなど）は
/// `fromScreenOffsetSync` を実装せず、`fromScreenOffset` の async だけ実装する。
/// コアは同期変換の有無を見て経路を変える。
public final class TemplateViewHolder: MapViewHolderProtocol {
    public let mapView: TemplateMap
    public let map: TemplateMap

    init(map: TemplateMap) {
        self.mapView = map
        self.map = map
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        map.screenPoint(for: position)
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        map.geoPoint(at: offset)
    }

    /// ビューポートの大きさ。`buildVisibleRegion()` が 4 隅を逆投影するのに使う。
    ///
    /// **既定実装は `mapView as? UIView` の `bounds.size` を返す。**
    /// SDK の地図ビューが `UIView` ならそのままでよく、ここは書かなくてよい。
    /// この雛形のように `UIView` でない場合（WebView ブリッジや、地図が
    /// `UIView` を公開しない SDK）は override が要る。
    ///
    /// **書き忘れると `visibleRegion` が黙って nil になる。**
    /// アプリからは「`cameraPosition.visibleRegion` がいつも nil」という形で出る。
    /// `TemplateDriverConformanceTests.testCameraRoundTrips` がここを見ている。
    public func viewportSizePx() -> CGSize? {
        let size = map.sizePx
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }
}

// ============================================================================
// C. 地図デザイン型（実装点 3 つ）
// ============================================================================

/// 実装点 C。SDK のスタイル指定を表す型。文字列でも enum でも、SDK の型そのままでもよい。
public struct TemplateMapDesignType: Equatable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

public enum TemplateMapDesign {
    public static let standard = TemplateMapDesignType(id: "standard")
    public static let satellite = TemplateMapDesignType(id: "satellite")
}

// ============================================================================
// F. ドラッグ中のパン抑止（実装点 1 つ）
// ============================================================================

/// 実装点 F。コアの ``DefaultMarkerEventController`` が掴んでいる間だけパンを切る。
///
/// **「掴む前の値へ戻す」のはコアがやる。**ここは素直に読み書きするだけでよい。
/// 無条件に `true` を書き戻す実装をここに入れると、アプリが
/// `uiSettings.scrollGesture = false` にしていた地図がドラッグ後に動くようになる。
@MainActor
final class TemplateMarkerDragSurface: MarkerDragSurface {
    private weak var map: TemplateMap?

    init(map: TemplateMap) { self.map = map }

    var isScrollEnabled: Bool {
        get { map?.isScrollEnabled ?? true }
        set { map?.isScrollEnabled = newValue }
    }

    func geoPoint(atScreenPoint point: CGPoint) -> GeoPoint? {
        map?.geoPoint(at: point)
    }
}
