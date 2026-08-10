import CoreGraphics
import MapConductorCore
import XCTest
@testable import MapConductorForTemplate

/// 新しいドライバーを書いたら、**まずこのファイルをコピーして**
/// `Template` を自分の SDK 名に置き換える。
///
/// ## これが緑でも実機確認は省略できない
///
/// マーカーの描画は `UIImage` を通り、当たり判定は実際のビューの大きさに依存する。
/// タップとドラッグは実機で見るしかない。特にドラッグは
/// **指が下りている間**のフレームを見ること（離すとマーカーは最終位置へ
/// スナップするので、壊れていても前後比較では正しく見える）。
@MainActor
final class TemplateDriverConformanceTests: XCTestCase {
    private func makeController() -> TemplateMapViewController {
        TemplateMapViewController(map: TemplateMap())
    }

    /// **これが最重要。**
    ///
    /// `registerOverlayController` の呼び忘れも、`SlottedOverlayController` の
    /// 実装漏れも、症状は同じ「黙って何も起きない」。ビルドも API チェックも
    /// 既存のテストも緑のまま通ってしまう。ここで機械的に捕まえる。
    func testEveryOverlayKindIsReachable() throws {
        let controller = makeController()
        try MapDriverConformance.checkOverlaySlots(controller.overlayControllers.all())
    }

    func testZoomConverterRoundTrips() throws {
        try MapDriverConformance.checkZoomConverter(makeController().zoomConverter)
    }

    func testCascadeOrderIsCanonical() throws {
        try MapDriverConformance.checkCascadeOrder()
    }

    /// `unsupported` の宣言に理由が付いているか。
    /// 理由が無いと、機能が止まった理由がアプリ開発者に伝わらない。
    func testCapabilityDeclarationsAreMeaningful() throws {
        let registry = MutableMapServiceRegistry()
        makeController().declareCapabilities(into: registry)
        try MapDriverConformance.checkCapabilityDeclarations(registry)
    }

    /// 投影の往復。同期変換を持つドライバーだけ呼ぶ。
    ///
    /// ここがずれていると、InfoBubble が地図の動きに追従しない・
    /// タイル方式マーカーがタップできない、という形で出る。
    func testProjectionRoundTrips() throws {
        let map = TemplateMap()
        map.center = GeoPoint(latitude: 35.681, longitude: 139.767, altitude: 0)
        map.zoom = 12
        let holder = TemplateViewHolder(map: map)

        try MapDriverConformance.checkProjectionRoundTrip(
            toScreen: { holder.toScreenOffset(position: $0) },
            fromScreen: { holder.fromScreenOffsetSync(offset: $0) },
            samples: [
                GeoPoint(latitude: 35.681, longitude: 139.767, altitude: 0),
                GeoPoint(latitude: 0, longitude: 0, altitude: 0),
                GeoPoint(latitude: 35.7, longitude: 139.8, altitude: 0),
                GeoPoint(latitude: -33.86, longitude: 151.2, altitude: 0),
            ]
        )
    }

    /// カメラの往復。統一ズーム → SDK の生ズーム → 統一ズーム。
    /// ここがずれると、当たり判定の許容量が実際の縮尺と食い違う。
    func testCameraRoundTrips() throws {
        let map = TemplateMap()
        let controller = TemplateMapViewController(map: map)
        let requested = MapCameraPosition(
            position: GeoPoint(latitude: 35.681, longitude: 139.767, altitude: 0),
            zoom: 14.5,
            bearing: 30,
            tilt: 45
        )
        controller.moveCamera(position: requested)

        let read = controller.readNativeCamera()
        XCTAssertEqual(read.position.latitude, requested.position.latitude, accuracy: 1e-9)
        XCTAssertEqual(read.zoom, requested.zoom, accuracy: 1e-9)
        XCTAssertEqual(read.bearing, requested.bearing, accuracy: 1e-9)
        XCTAssertEqual(read.tilt, requested.tilt, accuracy: 1e-9)
        XCTAssertNotNil(read.visibleRegion, "visibleRegion はコアが載せる。nil ならホルダーの投影が動いていない")
    }
}
