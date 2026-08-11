import MapConductorCore
import XCTest
@testable import MapConductorForOpenMobileMaps

/// android-for-openmobilemaps の適合テストの tilt 部分と**同じ主張**。
/// 2D カメラにピッチが無いので、傾きはカメラ位置の付け替えで表現している。
/// 前進量が他プロバイダとずれると、同じ tilt でも見える範囲が変わる。
final class TiltEmulationTests: XCTestCase {
    func testNonNegativeTiltLeavesTheCameraAlone() {
        let position = MapCameraPosition(
            position: GeoPoint(latitude: 35.681, longitude: 139.767),
            zoom: 14.0,
            bearing: 30.0,
            tilt: 45.0
        )
        let shifted = OpenMobileMapsTiltEmulation.shiftedCamera(position)
        XCTAssertEqual(shifted.center.latitude, 35.681, accuracy: 1e-12)
        XCTAssertEqual(shifted.center.longitude, 139.767, accuracy: 1e-12)
        XCTAssertEqual(shifted.zoom, 14.0, accuracy: 1e-12)
    }

    func testNegativeTiltMovesForwardAndRestores() {
        let origin = GeoPoint(latitude: 35.681, longitude: 139.767)
        let position = MapCameraPosition(position: origin, zoom: 14.0, bearing: 90.0, tilt: -45.0)

        let shifted = OpenMobileMapsTiltEmulation.shiftedCamera(position)
        let forward = Spherical.computeDistanceBetween(from: origin, to: shifted.center)
        XCTAssertGreaterThan(forward, 1.0, "tilt < 0 では中心が進行方向へ前進していなければならない")
        XCTAssertLessThan(shifted.zoom, 14.0, "tilt < 0 ではズームが引かれる")

        let restored = OpenMobileMapsTiltEmulation.restoreLogicalCamera(
            center: shifted.center,
            zoom: shifted.zoom,
            bearing: 90.0,
            logicalTilt: -45.0
        )
        XCTAssertEqual(restored.zoom, 14.0, accuracy: 1e-9)

        // 完全一致はしない。巻き戻しの視距離を「前進後の緯度」で計算するため（ArcGIS2D も同じ）。
        // 前進量に対して十分小さければよい。
        let residual = Spherical.computeDistanceBetween(from: origin, to: restored.center)
        XCTAssertLessThan(
            residual, forward * 0.01,
            "巻き戻しの誤差が大きすぎる（前進 \(forward) m に対し残差 \(residual) m）"
        )
    }

    /// 定数が android と同じであること。ここがずれると同じ tilt で見える範囲が変わる。
    func testMaxTiltMatchesAndroid() {
        XCTAssertEqual(OpenMobileMapsTiltEmulation.maxTiltDegrees, 60.0)
    }
}
