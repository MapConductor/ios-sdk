import UIKit
import MapConductorCore
import XCTest

import MapConductorVectorTile

/**
 Exercises the path a map backend actually takes: provider ->
 `LocalTileServer` route -> URL template -> HTTP -> PNG.

 Source tiles come from a bundled asset rather than the network, so the test
 measures the SDK plumbing and not connectivity.
 */
final class VectorTileProviderTests: XCTestCase {

    private var styleJSON: String!
    private var tileData: Data!
    private var provider: VectorTileProvider!
    private let routeId = "vectortile-test"

    override func setUpWithError() throws {
        let bundle = Bundle.module
        styleJSON = try String(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "demo-style", withExtension: "json")),
            encoding: .utf8
        )
        tileData = try Data(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "tile-0-0-0", withExtension: "pbf"))
        )
        // Serve the bundled tile for whatever the plan asks for.
        provider = try VectorTileProvider(styleJSON: styleJSON, tileSize: 512) { [tileData] _ in
            tileData
        }
    }

    override func tearDown() {
        TileServerRegistry.get().unregister(routeId: routeId)
        provider?.close()
        provider = nil
    }

    func testServesAPngThroughTheLocalTileServer() throws {
        let server = TileServerRegistry.get()
        server.register(routeId: routeId, provider: provider)

        let template = server.urlTemplate(routeId: routeId, tileSize: 512)
        XCTAssertTrue(template.contains(routeId), "unexpected template: \(template)")

        let url = try XCTUnwrap(
            URL(
                string: template
                    .replacingOccurrences(of: "{z}", with: "0")
                    .replacingOccurrences(of: "{x}", with: "0")
                    .replacingOccurrences(of: "{y}", with: "0")
            )
        )

        let received = expectation(description: "tile fetched")
        var payload: Data?
        var status = 0
        URLSession.shared.dataTask(with: url) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            payload = data
            received.fulfill()
        }.resume()
        wait(for: [received], timeout: 20)

        XCTAssertEqual(status, 200)
        let png = try XCTUnwrap(payload)
        XCTAssertGreaterThan(png.count, 10_000)

        // Pixels, not points: tiles are drawn at the display's scale so a
        // Retina screen is not handed an image to stretch. The raster layer
        // still declares 512, which is what sets how large the map looks.
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(image.width, 512 * Int(UIScreen.main.scale.rounded()))
    }

    func testRendersDirectlyThroughTheProviderInterface() throws {
        let png = try XCTUnwrap(provider.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
        XCTAssertGreaterThan(png.count, 10_000)
    }

    /// `symbol` used to appear here as a type nothing could draw. It is drawn
    /// now, so this style has nothing left to complain about.
    func testReportsNothingWrongWithAStyleItCanDraw() {
        XCTAssertEqual(provider.diagnostics(), [])
    }

    /// A style it genuinely cannot draw still has to say so: the failure mode
    /// that matters is a tile that is quietly missing something.
    func testReportsStyleDiagnostics() throws {
        let hillshaded = try VectorTileProvider(
            styleJSON: """
            {"version": 8, "sources": {}, "layers": [{"id": "h", "type": "hillshade"}]}
            """,
            renderMode: .cpu
        ) { _ in nil }
        defer { hillshaded.close() }
        let messages = hillshaded.diagnostics()
        XCTAssertTrue(messages.contains { $0.contains("hillshade") }, "\(messages)")
    }

    func testRestylingChangesOutputWithoutRefetching() throws {
        var fetches = 0
        let subject = try VectorTileProvider(styleJSON: styleJSON, tileSize: 256) { [tileData] _ in
            fetches += 1
            return tileData
        }
        defer { subject.close() }

        let before = try XCTUnwrap(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
        let afterFirstRender = fetches

        try subject.setStyle(
            """
            {"version":8,"sources":{},"layers":[
              {"id":"bg","type":"background","paint":{"background-color":"#ff0000"}}
            ]}
            """
        )
        let after = try XCTUnwrap(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))

        XCTAssertNotEqual(before, after, "restyle should change the pixels")
        // Geometry is unchanged, so the cache serves the second render.
        XCTAssertEqual(fetches, afterFirstRender)
    }

    func testClosedProviderStopsServing() throws {
        let subject = try VectorTileProvider(styleJSON: styleJSON) { [tileData] _ in tileData }
        subject.close()
        subject.close()
        XCTAssertNil(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
    }
}
