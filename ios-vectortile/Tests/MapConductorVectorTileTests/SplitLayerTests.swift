import MapConductorCore
import XCTest

import MapConductorVectorTile

/**
 Covers what the provider gained when iOS caught up with Android: the split
 ground/label layers, glyph warming, and the credits a style asks for.

 Source tiles and the glyph range come from bundled assets, so nothing here
 touches the network. Every fetch is counted, because half of what this layer
 does is decide what *not* to ask for.
 */
final class SplitLayerTests: XCTestCase {
    private var styleJSON: String!
    private var tileData: Data!
    private var glyphData: Data!

    /**
     Not z0: the demo style gives `geolines-label` a minzoom of 1 and
     `countries-label` a minzoom of 2, so at z0 no symbol layer applies and
     there is correctly nothing to label. z2 has both, plus the ring of
     neighbours the label pass asks for.
     */
    private let target = TileRequest(x: 1, y: 1, z: 2)

    override func setUpWithError() throws {
        let bundle = Bundle.module
        styleJSON = try String(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "demo-style", withExtension: "json")),
            encoding: .utf8
        )
        tileData = try Data(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "tile-0-0-0", withExtension: "pbf"))
        )
        glyphData = try Data(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "glyphs-0-255", withExtension: "pbf"))
        )
    }

    /// Answers every source tile from the bundle and every glyph range from the
    /// fixture, recording what was asked for.
    private func provider(
        onFetch: ((URL) -> Void)? = nil
    ) throws -> VectorTileProvider {
        let tile = tileData!
        let glyphs = glyphData!
        return try VectorTileProvider(
            styleJSON: styleJSON,
            tileSize: 256,
            renderMode: .cpu
        ) { url in
            onFetch?(url)
            // Source tiles and glyph ranges are both .pbf on the same host;
            // only the path separates them.
            return url.path.contains("/font/") ? glyphs : tile
        }
    }

    private func isPng(_ data: Data?) -> Bool {
        guard let data, data.count > 4 else { return false }
        return Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]
    }

    /// Waits for a condition the provider reaches on its own threads.
    private func eventually(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(condition(), description)
    }

    // MARK: - The two halves

    func testBothHalvesDrawAPng() throws {
        let subject = try provider()
        defer { subject.close() }
        XCTAssertTrue(isPng(subject.groundTiles.renderTile(request: target)), "ground")
        XCTAssertTrue(isPng(subject.labelTiles.renderTile(request: target)), "labels")
        XCTAssertTrue(isPng(subject.renderTile(request: target)), "both in one")
    }

    /**
     The point of the split: the ground is drawn once and a font landing must
     not change it. If it did, every glyph range would redraw the whole map
     rather than the transparent half.
     */
    func testGlyphsArrivingDoNotChangeTheGround() throws {
        let subject = try provider()
        defer { subject.close() }

        let before = subject.groundTiles.renderTile(request: target)
        XCTAssertTrue(isPng(before))

        // Draw labels, which warms the glyph ranges as a side effect.
        _ = subject.labelTiles.renderTile(request: target)
        eventually("glyphs never arrived") { subject.glyphGenerationValue > 0 }

        XCTAssertEqual(before, subject.groundTiles.renderTile(request: target))
    }

    /**
     Labels appear only once their glyphs are in.

     Compared against a provider whose glyph fetches all fail rather than
     against an earlier render of the same one: the fixture answers instantly,
     so the range lands before the first tile is drawn and there is no "before"
     to catch. What is being asserted is the end state either way -- ink on the
     tile when the font is available, none when it is not.
     */
    func testLabelsNeedTheirGlyphs() throws {
        let withFont = try provider()
        defer { withFont.close() }
        _ = withFont.labelTiles.renderTile(request: target)
        eventually("glyphs never arrived") { withFont.glyphGenerationValue > 0 }
        let labelled = withFont.labelTiles.renderTile(request: target)

        let tile = tileData!
        let starved = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 256, renderMode: .cpu
        ) { url in url.path.contains("/font/") ? nil : tile }
        defer { starved.close() }
        let bare = starved.labelTiles.renderTile(request: target)

        XCTAssertTrue(isPng(labelled))
        XCTAssertTrue(isPng(bare))
        XCTAssertGreaterThan(
            labelled!.count, bare!.count,
            "the labelled tile carries ink the starved one does not"
        )
    }

    /**
     The ground never draws a label, so the ring of neighbours the label pass
     asks for is nine fetches it has no use for.
     */
    func testTheGroundSkipsTheLabelOnlyNeighbours() throws {
        // The provider fetches a plan in parallel, so the recorder is shared
        // across threads and has to be guarded.
        let lock = NSLock()
        var groundUrls = Set<String>()
        let ground = try provider { url in
            lock.lock()
            groundUrls.insert(url.absoluteString)
            lock.unlock()
        }
        _ = ground.groundTiles.renderTile(request: target)
        ground.close()

        var labelUrls = Set<String>()
        let labels = try provider { url in
            lock.lock()
            labelUrls.insert(url.absoluteString)
            lock.unlock()
        }
        _ = labels.labelTiles.renderTile(request: target)
        labels.close()

        lock.lock()
        defer { lock.unlock() }

        let groundTiles = groundUrls.filter { !$0.contains("/font/") }
        let labelTiles = labelUrls.filter { !$0.contains("/font/") }
        XCTAssertLessThan(
            groundTiles.count, labelTiles.count,
            "the ground fetched the label pass's neighbours"
        )
    }

    // MARK: - Fetching

    /// Two halves of the same tile want the same sources. Fetching them twice
    /// is the difference between one viewport of traffic and two.
    func testFetchesEachSourceOnce() throws {
        var counts: [String: Int] = [:]
        let lock = NSLock()
        let subject = try provider { url in
            lock.lock()
            counts[url.absoluteString, default: 0] += 1
            lock.unlock()
        }
        defer { subject.close() }

        _ = subject.groundTiles.renderTile(request: target)
        _ = subject.labelTiles.renderTile(request: target)

        let repeated = counts.filter { !$0.key.contains("/font/") && $0.value > 1 }
        XCTAssertTrue(repeated.isEmpty, "fetched more than once: \(repeated)")
    }

    /// A map that has moved on is not owed the tile it stopped waiting for.
    func testGivesUpOnACancelledTile() throws {
        let subject = try provider()
        defer { subject.close() }
        XCTAssertNil(subject.renderTile(request: target, content: .full) { true })
    }

    // MARK: - Giving up and remembering

    /**
     A tile the map stopped waiting for must not be drawn: renderers are a
     fixed resource, so a doomed tile is drawn *instead of* one still on
     screen.
     */
    func testGivesUpOnACancelledTileThroughTheProtocol() throws {
        let subject = try provider()
        defer { subject.close() }
        // The protocol method, which is what the tile server calls.
        let asProvider: TileProvider = subject
        XCTAssertNil(try asProvider.renderTile(request: target, isCancelled: { true }))
        XCTAssertNotNil(try asProvider.renderTile(request: target, isCancelled: { false }))
    }

    /// Each half has to honour it too, or half the map keeps drawing.
    func testBothHalvesGiveUp() throws {
        let subject = try provider()
        defer { subject.close() }
        XCTAssertNil(try subject.groundTiles.renderTile(request: target, isCancelled: { true }))
        XCTAssertNil(try subject.labelTiles.renderTile(request: target, isCancelled: { true }))
    }

    /**
     A second launch must not redraw what the first drew.

     Two providers over one directory stand in for two launches: the second one
     is given no network at all, so anything it serves came off disk.
     */
    func testRemembersRenderedTilesAcrossLaunches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vectortile-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let tile = tileData!
        let first = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 256, renderMode: .cpu,
            assetCacheDirectory: directory
        ) { url in url.path.contains("/font/") ? nil : tile }
        let drawn = first.groundTiles.renderTile(request: target)
        first.close()
        XCTAssertTrue(isPng(drawn))

        var fetches = 0
        let second = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 256, renderMode: .cpu,
            assetCacheDirectory: directory
        ) { _ in
            fetches += 1
            return nil
        }
        defer { second.close() }
        let served = second.groundTiles.renderTile(request: target)

        XCTAssertEqual(served, drawn, "the second launch redrew the tile")
        XCTAssertEqual(fetches, 0, "the second launch went to the network")
    }

    /// A restyle must not serve the old style's pixels. The key carries the
    /// style, so the old tiles simply stop being found.
    func testARestyleStopsFindingTheOldTiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vectortile-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let tile = tileData!
        let subject = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 256, renderMode: .cpu,
            assetCacheDirectory: directory
        ) { url in url.path.contains("/font/") ? nil : tile }
        defer { subject.close() }

        let before = subject.groundTiles.renderTile(request: target)
        // Same layers, different background colour.
        let restyled = styleJSON.replacingOccurrences(of: "#D8F2FF", with: "#FF0000")
        XCTAssertNotEqual(restyled, styleJSON, "the fixture no longer has that colour")
        try subject.setStyle(restyled)
        let after = subject.groundTiles.renderTile(request: target)

        XCTAssertTrue(isPng(before) && isPng(after))
        XCTAssertNotEqual(before, after, "the restyle served the cached tile")
    }

    // MARK: - Credits

    func testCarriesTheCreditOutOfTheStyle() throws {
        let credited = try VectorTileProvider(
            styleJSON: """
            {"version": 8,
             "sources": {"osm": {"type": "vector",
                                 "tiles": ["https://example.com/{z}/{x}/{y}.pbf"],
                                 "attribution": "&copy; OpenStreetMap"}},
             "layers": [{"id": "w", "type": "fill", "source": "osm", "source-layer": "water"}]}
            """,
            renderMode: .cpu
        ) { _ in nil }
        defer { credited.close() }
        XCTAssertEqual(credited.attributions(), ["&copy; OpenStreetMap"])
    }

    func testInventsNoCreditWhenTheStyleAsksForNone() throws {
        let subject = try provider()
        defer { subject.close() }
        XCTAssertTrue(subject.attributions().isEmpty)
    }
}
