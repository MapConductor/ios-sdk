import UIKit
import XCTest
@testable import MapConductorKML

/// ポリゴンのヒット判定。ピクセル許容差（lineTolSq）を渡しても内部（穴を除く）は
/// 当たり、輪郭のすぐ外側は許容差の範囲で拾い、穴の中と遠方は外れる。
/// android-sdk / react-sdk の同名テストと同じ期待値。
final class KMLHitTesterTests: XCTestCase {
    // sample.kml と同じ皇居ポリゴン: 外環 139.744-139.762 / 35.676-35.688、
    // 穴 139.750-139.756 / 35.680-35.685
    private let polygonKML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
      <Placemark>
        <name>poly</name>
        <Polygon>
          <outerBoundaryIs><LinearRing><coordinates>
            139.744,35.688 139.762,35.688 139.762,35.676 139.744,35.676 139.744,35.688
          </coordinates></LinearRing></outerBoundaryIs>
          <innerBoundaryIs><LinearRing><coordinates>
            139.750,35.685 139.756,35.685 139.756,35.680 139.750,35.680 139.750,35.685
          </coordinates></LinearRing></innerBoundaryIs>
        </Polygon>
      </Placemark>
    </Document></kml>
    """

    private func makeRenderer() throws -> KMLTileRenderer {
        let renderer = KMLTileRenderer(tileSize: 512)
        let features = try KMLParser.parse(polygonKML)
        renderer.update(
            features: features,
            layerStyle: KMLTileRenderer.LayerStyle(
                strokeColor: .red,
                fillColor: .blue,
                strokeWidth: 3,
                pointRadius: 8
            )
        )
        return renderer
    }

    /// processClick(pixelTolerance: 12, zoom: 13) が計算するのと同じ許容差。
    private var lineTolSq: Double {
        let worldSize = 512.0 * pow(2.0, 13.0)
        let lineTol = 12.0 / worldSize
        return lineTol * lineTol
    }

    func testInteriorHitsEvenWithPixelTolerance() throws {
        let renderer = try makeRenderer()
        let hit = renderer.hitTest(longitude: 139.746, latitude: 35.683, lineTolSq: lineTolSq)
        XCTAssertEqual("poly", hit?.feature.properties["name"] as? String)
    }

    func testHoleMissesEvenWithPixelTolerance() throws {
        let renderer = try makeRenderer()
        XCTAssertNil(renderer.hitTest(longitude: 139.753, latitude: 35.6825, lineTolSq: lineTolSq))
    }

    func testJustOutsideOutlineHitsWithinTolerance() throws {
        // 西端 139.744 のすぐ外側（約 45m）。12px@z13 ≒ 114m の許容差に収まる。
        let renderer = try makeRenderer()
        let hit = renderer.hitTest(longitude: 139.7435, latitude: 35.683, lineTolSq: lineTolSq)
        XCTAssertEqual("poly", hit?.feature.properties["name"] as? String)
    }

    func testFarOutsideMisses() throws {
        let renderer = try makeRenderer()
        XCTAssertNil(renderer.hitTest(longitude: 139.735, latitude: 35.683, lineTolSq: lineTolSq))
    }

    func testInteriorHitsAndHoleMissesWithDefaultTolerances() throws {
        let renderer = try makeRenderer()
        XCTAssertEqual(
            "poly",
            renderer.hitTest(longitude: 139.746, latitude: 35.683)?.feature.properties["name"] as? String
        )
        XCTAssertNil(renderer.hitTest(longitude: 139.753, latitude: 35.6825))
    }
}
