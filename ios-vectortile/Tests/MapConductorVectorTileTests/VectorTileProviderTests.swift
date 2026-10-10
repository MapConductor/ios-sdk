import UIKit
import MapConductorCore
import XCTest

@testable import MapConductorVectorTile

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

    func testReplacementReusesSourceTilesAfterPreviousProviderCloses() throws {
        let original = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 32, renderMode: .cpu, renderScale: 1
        ) { [tileData] _ in tileData }
        defer { original.close() }
        let request = TileRequest(x: 0, y: 0, z: 0)
        let before = try XCTUnwrap(original.renderTile(request: request, content: .ground))

        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(styleJSON.utf8)) as? [String: Any])
        var layers = try XCTUnwrap(document["layers"] as? [[String: Any]])
        for index in layers.indices {
            if layers[index]["type"] as? String == "fill" {
                layers[index]["paint"] = ["fill-color": "#ff0000"]
            }
        }
        document["layers"] = layers
        let changed = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: document), encoding: .utf8))
        let replacement = try VectorTileProvider(
            styleJSON: changed, tileSize: 32, renderMode: .cpu, renderScale: 1
        ) { _ in
            XCTFail("a paint change must reuse the previous provider's source bytes")
            return nil
        }
        defer { replacement.close() }
        replacement.reuseSourceTiles(from: original)
        original.close()
        let after = try XCTUnwrap(replacement.renderTile(request: request, content: .ground))
        XCTAssertNotEqual(before, after, "cached sources must still be painted with the new style")
    }

    func testAsyncCloseDuringSourceFetchStopsServingWithoutWaiting() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "cancelled render finished")
        let subject = try VectorTileProvider(styleJSON: styleJSON) { [tileData] _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return tileData
        }
        DispatchQueue.global().async {
            XCTAssertNil(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        let started = Date()
        subject.closeAsync()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertNil(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
        subject.closeAsync()
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testWaitersShareTheRetryAfterTheirSourceOwnerIsCancelled() throws {
        let firstEntered = DispatchSemaphore(value: 0)
        let firstRelease = DispatchSemaphore(value: 0)
        let retryEntered = DispatchSemaphore(value: 0)
        let retryRelease = DispatchSemaphore(value: 0)
        let waitersReady = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var attempts = 0
        var polls = [0, 0]
        var pixels: [Data?] = [nil, nil]
        var retryReleased = false
        var finishedEarly = false
        let subject = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 32, renderMode: .cpu, renderScale: 1
        ) { [tileData] _ in
            lock.lock(); attempts += 1; let attempt = attempts; lock.unlock()
            if attempt == 1 {
                firstEntered.signal()
                _ = firstRelease.wait(timeout: .now() + 5)
                return nil
            }
            retryEntered.signal()
            _ = retryRelease.wait(timeout: .now() + 5)
            return tileData
        }
        defer {
            firstRelease.signal()
            retryRelease.signal()
            subject.close()
        }
        let request = TileRequest(x: 0, y: 0, z: 0)
        let cancellation = FetchCancellation()
        let ownerFinished = expectation(description: "cancelled owner finished")
        DispatchQueue.global().async {
            XCTAssertNil(subject.renderTile(request: request, content: .ground) { cancellation.isCancelled })
            ownerFinished.fulfill()
        }
        XCTAssertEqual(firstEntered.wait(timeout: .now() + 2), .success)
        let waitersFinished = expectation(description: "both waiters received the source")
        waitersFinished.expectedFulfillmentCount = 2
        for index in 0..<2 {
            DispatchQueue.global().async {
                let png = subject.renderTile(request: request, content: .ground) {
                    lock.lock(); polls[index] += 1; let poll = polls[index]; lock.unlock()
                    if poll == 2 { waitersReady.signal() }
                    return false
                }
                lock.lock()
                finishedEarly = finishedEarly || !retryReleased
                pixels[index] = png
                lock.unlock()
                waitersFinished.fulfill()
            }
        }
        for _ in 0..<2 { XCTAssertEqual(waitersReady.wait(timeout: .now() + 2), .success) }
        cancellation.cancel()
        wait(for: [ownerFinished], timeout: 1)
        firstRelease.signal()
        XCTAssertEqual(retryEntered.wait(timeout: .now() + 2), .success)
        let held = expectation(description: "retry deliberately remains in flight")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { held.fulfill() }
        wait(for: [held], timeout: 1)
        lock.lock(); retryReleased = true; lock.unlock()
        retryRelease.signal()
        wait(for: [waitersFinished], timeout: 2)
        XCTAssertFalse(finishedEarly, "a waiter rendered without the still-loading source")
        XCTAssertEqual(attempts, 2, "waiters must share one retry")
        let expected = try XCTUnwrap(subject.renderTile(request: request, content: .ground))
        XCTAssertEqual(pixels[0], expected)
        XCTAssertEqual(pixels[1], expected)
    }

    func testWaitersShareTransportFailureAndDoNotCacheIncompletePixels() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let waiterReady = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var attempts = 0
        var polls = 0
        var pixels: [Data?] = [nil, nil]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let subject = try VectorTileProvider(
            styleJSON: styleJSON, tileSize: 32, renderMode: .cpu,
            assetCacheDirectory: directory, renderScale: 1
        ) { [tileData] _ in
            lock.lock(); attempts += 1; let attempt = attempts; lock.unlock()
            if attempt == 1 {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
                throw URLError(.timedOut)
            }
            return tileData
        }
        defer {
            release.signal()
            subject.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let request = TileRequest(x: 0, y: 0, z: 0)
        let finished = expectation(description: "both renders recover from the shared failure")
        finished.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            let png = subject.renderTile(request: request, content: .ground)
            lock.lock(); pixels[0] = png; lock.unlock()
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            let png = subject.renderTile(request: request, content: .ground) {
                lock.lock(); polls += 1; let poll = polls; lock.unlock()
                if poll == 2 { waiterReady.signal() }
                return false
            }
            lock.lock(); pixels[1] = png; lock.unlock()
            finished.fulfill()
        }
        XCTAssertEqual(waiterReady.wait(timeout: .now() + 2), .success)
        release.signal()
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(attempts, 1, "one timeout must not be retried once per waiter")
        let recovered = try XCTUnwrap(subject.renderTile(request: request, content: .ground))
        XCTAssertEqual(attempts, 2)
        XCTAssertNotEqual(pixels[0], recovered)
        XCTAssertNotEqual(pixels[1], recovered, "incomplete waiter output must not enter the PNG cache")
    }

    func testRetainedLayerStopsServingAfterProviderIsReleased() throws {
        var subject: VectorTileProvider? = try VectorTileProvider(
            styleJSON: "{\"version\":8,\"sources\":{},\"layers\":[]}"
        ) { _ in nil }
        let layer = subject!.groundTiles
        weak var released = subject
        subject?.close()
        subject = nil
        // Asset warming may already have borrowed the owner on its queue.
        let deadline = Date().addingTimeInterval(5)
        while released != nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNil(released)
        XCTAssertNil(layer.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
    }

    func testClosedProviderStopsServing() throws {
        let subject = try VectorTileProvider(styleJSON: styleJSON) { [tileData] _ in tileData }
        subject.close()
        subject.close()
        XCTAssertNil(subject.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
    }
}
