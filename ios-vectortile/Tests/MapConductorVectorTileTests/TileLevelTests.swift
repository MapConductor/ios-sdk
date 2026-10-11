import XCTest
import MapConductorCore
@testable import MapConductorVectorTile

final class TileLevelTests: XCTestCase {
    func testGoogleSizedTilesUseTheSameSourceLevelAs512PointTiles() throws {
        let style = """
        {"version":8,"sources":{"v":{"type":"vector","tiles":["https://tiles.test/{z}/{x}/{y}.pbf"]}},
        "layers":[{"id":"roads","type":"line","source":"v","source-layer":"roads"}]}
        """
        let google = try VectorTileRenderer(styleJSON: style, displayTileSize: 256)
        let other = try VectorTileRenderer(styleJSON: style, displayTileSize: 512)
        defer { google.close(); other.close() }
        let first = try google.plan(z: 8, x: 226, y: 100)
        let second = try other.plan(z: 7, x: 113, y: 50)
        let plans = try [first, second].map { json in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        }
        XCTAssertEqual(plans[0].first?["z"] as? Int, 7)
        XCTAssertEqual(plans[0].first?["url"] as? String, plans[1].first?["url"] as? String)
    }
    func testSourceOffsetChangesDataWithoutLeakingToTheNextCall() throws {
        let style = """
        {"version":8,"sources":{"v":{"type":"vector","tiles":["https://tiles.test/{z}/{x}/{y}.pbf"]}},
        "layers":[{"id":"roads","type":"line","source":"v","source-layer":"roads"}]}
        """
        let renderer = try VectorTileRenderer(styleJSON: style, displayTileSize: 256)
        defer { renderer.close() }
        func sourceLevel(_ offset: Int) throws -> Int? {
            let plan = try renderer.plan(z: 8, x: 226, y: 100, sourceZoomOffset: offset)
            let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(plan.utf8)) as? [[String: Any]])
            return entries.first?["z"] as? Int
        }
        XCTAssertEqual(try sourceLevel(0), 7)
        XCTAssertEqual(try sourceLevel(1), 6)
        XCTAssertEqual(try sourceLevel(0), 7)
    }

    func testProviderDoesNotReuseAnImageFromAnotherSourceLevel() throws {
        let style = """
        {"version":8,"sources":{"v":{"type":"vector","tiles":["https://tiles.test/{z}/{x}/{y}.pbf"]}},
        "layers":[{"id":"roads","type":"line","source":"v","source-layer":"countries"}]}
        """
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "tile-0-0-0", withExtension: "pbf"))
        let tile = try Data(contentsOf: fixture)
        let lock = NSLock()
        var paths: [String] = []
        let provider = try VectorTileProvider(styleJSON: style, tileSize: 256, renderMode: .cpu) { url in
            lock.lock()
            paths.append(url.path)
            lock.unlock()
            return tile
        }
        defer { provider.close() }
        let normal = TileRequest(x: 226, y: 100, z: 8)
        let coarse = TileRequest(x: 226, y: 100, z: 8, sourceZoomOffset: 1)
        XCTAssertNotNil(provider.groundTiles.renderTile(request: normal))
        XCTAssertNotNil(provider.groundTiles.renderTile(request: coarse))
        XCTAssertTrue(paths.contains("/7/113/50.pbf"))
        XCTAssertTrue(paths.contains("/6/56/25.pbf"))
        let count = paths.count
        XCTAssertNotNil(provider.groundTiles.renderTile(request: normal))
        XCTAssertEqual(paths.count, count)
    }

}
