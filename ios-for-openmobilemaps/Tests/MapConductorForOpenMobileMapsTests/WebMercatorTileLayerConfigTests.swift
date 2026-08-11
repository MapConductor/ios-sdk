import MapConductorCore
import XCTest
@testable import MapConductorForOpenMobileMaps

/// android-for-openmobilemaps の適合テストのタイル部分と**同じ主張**。
///
/// レベルの縮尺が統一ズームとずれると、統一ズーム Z のときに 1 段低いレベルのタイルが
/// 選ばれて**常にぼやける**。表示はされるので気づきにくい。
final class WebMercatorTileLayerConfigTests: XCTestCase {
    private let converter = OpenMobileMapsZoomAltitudeConverter()

    func testTileUrlFlipsYForTms() {
        let xyz = WebMercatorTileLayerConfig(
            layerName: "test",
            urlTemplate: "https://example.test/{z}/{x}/{y}.png",
            tileSize: 256,
            scheme: .XYZ
        )
        let tms = WebMercatorTileLayerConfig(
            layerName: "test",
            urlTemplate: "https://example.test/{z}/{x}/{y}.png",
            tileSize: 256,
            scheme: .TMS
        )
        XCTAssertEqual(xyz.getTileUrl(2, y: 1, t: 0, zoom: 3), "https://example.test/3/2/1.png")
        // TMS は y が反転する。2^3 - 1 - 1 = 6。
        XCTAssertEqual(tms.getTileUrl(2, y: 1, t: 0, zoom: 3), "https://example.test/3/2/6.png")
    }

    /// 256pt タイルは、レベル L の縮尺が統一ズーム L の縮尺と厳密に一致すること。
    func test256PointTileLevelMatchesUnifiedZoom() {
        for level in 0 ... 20 {
            XCTAssertEqual(
                zoomScaleForLevel(level: level, tileSize: 256),
                converter.toNativeZoom(Double(level)),
                accuracy: converter.toNativeZoom(Double(level)) * 1e-9,
                "レベル \(level) の縮尺が統一ズーム \(level) と一致しない"
            )
        }
    }

    /// 512pt タイルは 256pt の 2 枚ぶんを覆うので、同じ画面には 1 段浅いレベルでよい。
    /// ＝ 同じレベルなら、512pt 側の縮尺の分母は 256pt 側の半分になる。
    func test512PointTileIsOneLevelShallower() {
        let small = zoomScaleForLevel(level: 10, tileSize: 256)
        let large = zoomScaleForLevel(level: 10, tileSize: 512)
        XCTAssertEqual(large * 2.0, small, accuracy: small * 1e-9)
    }
}
