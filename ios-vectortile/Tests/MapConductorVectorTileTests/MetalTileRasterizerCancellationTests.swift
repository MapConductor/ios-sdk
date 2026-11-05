import XCTest
@testable import MapConductorVectorTile

final class MetalTileRasterizerCancellationTests: XCTestCase {
    func testCancellationReleasesAWaiterWhileTheGPUIsStillBusy() throws {
        guard let gpu = MetalTileRasterizer.createOrNull(tileSize: 32) else {
            throw XCTSkip("Metal unavailable")
        }
        let renderer = try VectorTileRenderer(styleJSON:
            "{\"version\":8,\"sources\":{},\"layers\":[{\"id\":\"bg\",\"type\":\"background\",\"paint\":{\"background-color\":\"#000000\"}}]}")
        let tile = try renderer.tessellate(z: 0, x: 0, y: 0, tileSize: 32, tiles: [])
        let busy = expectation(description: "first render owns GPU resources")
        let waiting = expectation(description: "second render waiting")
        let cancelled = expectation(description: "waiter cancelled before GPU becomes free")
        let finished = expectation(description: "first and current renders finish")
        finished.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let flag = Cancellation()
        DispatchQueue.global().async {
            XCTAssertNotNil(gpu.renderPng(tile) { _ in
                busy.fulfill()
                _ = release.wait(timeout: .now() + 5)
            })
            finished.fulfill()
        }
        wait(for: [busy], timeout: 2)
        DispatchQueue.global().async {
            waiting.fulfill()
            XCTAssertNil(gpu.renderPng(tile, isCancelled: { flag.isCancelled }))
            cancelled.fulfill()
        }
        wait(for: [waiting], timeout: 1)
        flag.cancel()
        wait(for: [cancelled], timeout: 1)
        DispatchQueue.global().async {
            XCTAssertNotNil(gpu.renderPng(tile, isCancelled: { false }))
            finished.fulfill()
        }
        release.signal()
        wait(for: [finished], timeout: 2)
    }

    private final class Cancellation {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.lock(); value = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
}
