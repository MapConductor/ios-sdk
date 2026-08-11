import MapConductorCore
import XCTest
@testable import MapConductorForOpenMobileMaps

/// android-for-openmobilemaps の適合テストのカメラ補間部分と**同じ主張**。
///
/// SDK のアニメーションは尺を指定できない（実測で常に約 300ms）ので、こちらで
/// フレームを刻んでいる。その補間がここ。
final class CameraAnimationTests: XCTestCase {
    private func camera(
        _ latitude: Double,
        _ longitude: Double,
        zoom: Double = 10.0,
        bearing: Double = 0.0,
        tilt: Double = 0.0
    ) -> MapCameraPosition {
        MapCameraPosition(
            position: GeoPoint(latitude: latitude, longitude: longitude),
            zoom: zoom,
            bearing: bearing,
            tilt: tilt
        )
    }

    func testEndpointsAreTheInputsThemselves() {
        let from = camera(35.681, 139.767, zoom: 10.0, bearing: 0.0, tilt: 0.0)
        let to = camera(21.3069, -157.8583, zoom: 14.0, bearing: 90.0, tilt: 30.0)

        let start = OpenMobileMapsCameraAnimation.interpolate(from: from, to: to, t: 0.0)
        XCTAssertEqual(start.position.latitude, 35.681, accuracy: 1e-9)
        XCTAssertEqual(start.position.longitude, 139.767, accuracy: 1e-9)
        XCTAssertEqual(start.zoom, 10.0, accuracy: 1e-9)

        let end = OpenMobileMapsCameraAnimation.interpolate(from: from, to: to, t: 1.0)
        XCTAssertEqual(end.position.latitude, 21.3069, accuracy: 1e-9)
        XCTAssertEqual(end.position.longitude, -157.8583, accuracy: 1e-9)
        XCTAssertEqual(end.zoom, 14.0, accuracy: 1e-9)
        XCTAssertEqual(end.bearing, 90.0, accuracy: 1e-9)
        XCTAssertEqual(end.tilt, 30.0, accuracy: 1e-9)
    }

    /// 緯度 0 と 60 の中点は、緯度で測ると 30 だがメルカトルでは約 35.2。
    /// 緯度を直接混ぜていると 30 になるので、これが取り違えを捕まえる。
    func testCenterMovesLinearlyInMercatorSpace() {
        let mid = OpenMobileMapsCameraAnimation.interpolate(from: camera(0, 0), to: camera(60, 0), t: 0.5)
        XCTAssertEqual(mid.position.latitude, 35.2, accuracy: 0.1)
    }

    /// 経度 170 → -170 は、太平洋を渡る 20 度が近い。
    /// 素直に線形補間すると 0 度（アフリカ沖）を通ってしまう。
    func testLongitudeTakesTheShorterWay() {
        let mid = OpenMobileMapsCameraAnimation.interpolate(from: camera(0, 170), to: camera(0, -170), t: 0.5)
        XCTAssertGreaterThan(
            abs(mid.position.longitude), 179.0,
            "日付変更線を跨ぐべき（実際 \(mid.position.longitude)）"
        )
    }

    func testBearingTakesTheShorterWay() {
        // 350 度 → 10 度 は +20 度。180 度側へ回ってはいけない。
        XCTAssertEqual(OpenMobileMapsCameraAnimation.interpolateBearing(from: 350, to: 10, t: 0.5), 0.0, accuracy: 1e-9)
        // 戻る向きも同じ。
        XCTAssertEqual(OpenMobileMapsCameraAnimation.interpolateBearing(from: 10, to: 350, t: 0.5), 0.0, accuracy: 1e-9)
        // 常に 0 以上 360 未満へ正規化される。
        let bearing = OpenMobileMapsCameraAnimation.interpolateBearing(from: 10, to: 350, t: 0.9)
        XCTAssertTrue(bearing >= 0 && bearing < 360)
    }

    func testEasingStopsAtBothEndsAndIsHalfwayAtTheMiddle() {
        XCTAssertEqual(OpenMobileMapsCameraAnimation.ease(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(OpenMobileMapsCameraAnimation.ease(1.0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(OpenMobileMapsCameraAnimation.ease(0.5), 0.5, accuracy: 1e-12)
        // 単調増加であること（ここが崩れるとカメラが戻る）。
        var previous = -1.0
        for step in 0 ... 100 {
            let eased = OpenMobileMapsCameraAnimation.ease(Double(step) / 100.0)
            XCTAssertGreaterThanOrEqual(eased, previous, "単調増加でない（step=\(step)）")
            previous = eased
        }
    }
}
