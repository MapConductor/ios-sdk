import XCTest
@testable import MapConductorVectorTile

/// Closing the renderer while a render is in flight.
///
/// The provider is rebuilt when the map under it changes its tile size, and
/// ArcGIS's tiles are drawn on a queue of their own, so a render was still
/// running when the old provider closed. Freeing the native renderer under
/// that call read freed memory, and the app went to the home screen a second
/// after switching to ArcGIS. android-sdk's binding hit the same fault.
///
/// A use-after-free does not fail reliably -- it corrupts, or crashes later,
/// or does nothing -- so this runs the race many times and treats surviving it
/// as the assertion, plus the one thing that *is* deterministic: a call that
/// starts after the close must throw rather than touch anything.
final class RendererCloseRaceTests: XCTestCase {
    private var styleJSON: String!
    private var tileData: Data!

    override func setUpWithError() throws {
        let bundle = Bundle.module
        styleJSON = try String(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "demo-style", withExtension: "json")),
            encoding: .utf8
        )
        tileData = try Data(
            contentsOf: try XCTUnwrap(bundle.url(forResource: "tile-0-0-0", withExtension: "pbf"))
        )
    }

    func testCloseWaitsForARenderInFlight() throws {
        for _ in 0..<40 {
            let renderer = try VectorTileRenderer(styleJSON: styleJSON, displayTileSize: 512)
            let plan = try renderer.plan(z: 0, x: 0, y: 0)
            XCTAssertFalse(plan.isEmpty)
            let tiles: [Data?] = [tileData]

            let started = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            var renderThrew = false
            let worker = Thread {
                started.signal()
                // Either it drew (close waited for it) or the close got in
                // first and it threw. Both are correct; a crash is not.
                for _ in 0..<3 {
                    do {
                        _ = try renderer.render(z: 0, x: 0, y: 0, tileSize: 512, tiles: tiles)
                    } catch {
                        renderThrew = true
                        break
                    }
                }
                finished.signal()
            }
            worker.start()
            XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
            renderer.close()
            XCTAssertEqual(finished.wait(timeout: .now() + 10), .success, "render never finished")

            // Deterministic half: after close, every call throws `.closed`.
            XCTAssertThrowsError(try renderer.plan(z: 0, x: 0, y: 0)) { error in
                guard case VectorTileError.closed = error else {
                    return XCTFail("expected .closed, got \(error)")
                }
            }
            _ = renderThrew
        }
    }
}
