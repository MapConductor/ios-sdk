import XCTest
@testable import MapConductorForOpenMobileMaps

/// android-for-openmobilemaps の `OpenMobileMapsDriverConformanceTest` のズーム部分と
/// **同じ主張**を置いてある。この SDK のズームは縮尺の分母なので、他のプロバイダの
/// ようにオフセットの足し算では変換できない。ここが狂うと、同じ統一ズームを渡しても
/// iOS と android で縮尺が変わり、並べて見比べるサンプルが成立しなくなる。
final class ZoomAltitudeConverterTests: XCTestCase {
    private let converter = OpenMobileMapsZoomAltitudeConverter()

    func testUnifiedZoomAndNativeScaleRoundTrip() {
        for zoom in [0.0, 1.0, 5.5, 10.0, 15.25, 19.0, 22.0] {
            let native = converter.toNativeZoom(zoom)
            let roundTrip = converter.toUnifiedZoom(native)
            XCTAssertEqual(roundTrip, zoom, accuracy: 1e-9, "統一ズーム \(zoom) -> 縮尺 \(native) で往復しない")
        }
    }

    /// 「ズームインすると縮尺が細かくなる」。符号を取り違えると地図が逆に動く。
    func testScaleDecreasesAsZoomIncreases() {
        var previous = Double.greatestFiniteMagnitude
        for zoom in 0...22 {
            let native = converter.toNativeZoom(Double(zoom))
            XCTAssertLessThan(native, previous, "縮尺が単調減少していない（zoom=\(zoom)）")
            previous = native
        }
    }

    /// `156543.033928 x 160 / 0.0254`。ここがずれると Google Maps と大きさが揃わない。
    func testScaleAtZoomZeroMatchesTheDerivedValue() {
        XCTAssertEqual(converter.toNativeZoom(0.0), 986_097_222.0, accuracy: 1.0)
        // 1 段ズームインで縮尺はちょうど半分。
        XCTAssertEqual(converter.toNativeZoom(1.0), converter.toNativeZoom(0.0) / 2.0, accuracy: 1e-6)
    }

    /// android と**同じ定数**であること。プラットフォーム間でここがずれるのが
    /// いちばん見つけにくい（どちらも単体では正しく見える）。
    func testScaleConstantMatchesAndroid() {
        XCTAssertEqual(OpenMobileMapsZoomAltitudeConverter.scaleAtZoom0, 986_097_222.0)
    }

    /// 0 や負の縮尺で落ちないこと。SDK は初期化前に 0 を返すことがある。
    func testNonPositiveScaleClampsToMinimumZoom() {
        XCTAssertEqual(converter.toUnifiedZoom(0.0), 0.0, accuracy: 1e-12)
        XCTAssertEqual(converter.toUnifiedZoom(-1.0), 0.0, accuracy: 1e-12)
    }
}
