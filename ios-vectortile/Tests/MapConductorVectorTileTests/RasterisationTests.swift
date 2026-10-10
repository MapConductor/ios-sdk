import MapConductorCore
import MapConductorVectorStyle
import UIKit
import XCTest
@testable import MapConductorVectorTile

final class RasterisationTests: XCTestCase {
    private final class Host: MapStyleHost {
        private let registry = MutableMapServiceRegistry()
        var serviceRegistry: MapServiceRegistry { registry }
        var tileServer: LocalTileServer { TileServerRegistry.get() }
        var mounted: [RasterLayerState] = []
        var removed: [String] = []
        func onStyleLoaded(_ block: @escaping () -> Void) -> MapStyleInstallation { .none }
        func upsertRaster(_ state: RasterLayerState) { mounted.append(state) }
        func removeRaster(id: String) { removed.append(id) }
        func report(_ diagnostics: [String]) {}
    }

    private func document(_ color: String, visible: Bool = false) -> String {
        """
        {"version":8,"sources":{},"layers":[
          {"id":"background","type":"background","paint":{"background-color":"\(color)"}},
          {"id":"labels","type":"symbol","layout":{"visibility":"\(visible ? "visible" : "none")"},"paint":{"text-color":"#ffffff"}}
        ]}
        """
    }

    private func settle(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition())
    }

    private func drainPendingUpdates() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func pixel(in state: RasterLayerState) throws -> [UInt8] {
        guard case let .urlTemplate(template, _, _, _, _, _) = state.source else {
            throw VectorTileError.styleRejected("expected raster URL")
        }
        let url = try XCTUnwrap(URL(string: template
            .replacingOccurrences(of: "{z}", with: "0")
            .replacingOccurrences(of: "{x}", with: "0")
            .replacingOccurrences(of: "{y}", with: "0")))
        let received = expectation(description: "rendered raster")
        var png: Data?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            png = data
            received.fulfill()
        }.resume()
        wait(for: [received], timeout: 5)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(png))?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return pixel
    }

    func testBurstPublishesOnlyLatestStyleAndKeepsUnchangedLabelLayer() throws {
        let host = Host()
        let work = VectorTileRasteriser(tileSize: 32, renderMode: .cpu, renderScale: 1)
            .install(host: host, styleJSON: document("#000000"), affects: .both)
        defer { work.dispose() }
        settle { host.mounted.count == 2 }
        XCTAssertFalse(host.mounted[1].visible, "hidden symbols should not request empty tiles")
        let labels = host.mounted[1].source
        for step in 1...40 {
            work.restyle(styleJSON: document(String(format: "#%06x", step)), affects: .both)
        }
        settle { host.mounted.count > 2 }
        drainPendingUpdates()
        XCTAssertEqual(host.mounted.count, 3, "a burst should publish only one ground update")
        XCTAssertEqual(try pixel(in: host.mounted[2]), [0, 0, 40, 255], "the final requested colour must reach the map")
        XCTAssertEqual(host.mounted.filter { $0.id.hasSuffix("-labels") }.map(\.source), [labels])

        // The compiler reports .none for returning to the authored style.
        // It is still a change relative to the pixels currently on screen.
        work.restyle(styleJSON: document("#000000"), affects: .none)
        settle { host.mounted.count == 4 }
        XCTAssertNotEqual(host.mounted[2].source, host.mounted[3].source)
        XCTAssertEqual(try pixel(in: host.mounted[3]), [0, 0, 0, 255])
        work.restyle(styleJSON: document("#000000", visible: true), affects: .labels)
        settle { host.mounted.count == 5 }
        XCTAssertTrue(host.mounted[4].id.hasSuffix("-labels"))
        XCTAssertTrue(host.mounted[4].visible)
    }

    func testDisposalPreventsPendingRestyleFromRemountingLayers() {
        let host = Host()
        let work = VectorTileRasteriser(tileSize: 32, renderMode: .cpu, renderScale: 1)
            .install(host: host, styleJSON: document("#000000"), affects: .both)
        settle { host.mounted.count == 2 }
        work.restyle(styleJSON: document("#ffffff"), affects: .ground)
        work.dispose()
        settle { host.removed.count == 2 }
        drainPendingUpdates()
        XCTAssertEqual(host.mounted.count, 2)
    }

    func testSourceChangesInvalidateBothHalves() throws {
        let before = try RasterStyleSnapshot(styleJSON: document("#000000"))
        let changed = document("#000000").replacingOccurrences(
            of: "\"sources\":{}", with: "\"sources\":{\"s\":{\"type\":\"vector\",\"tiles\":[\"https://example.com/{z}/{x}/{y}.pbf\"]}}")
        XCTAssertEqual(try RasterStyleSnapshot(styleJSON: changed).changes(from: before), .both)
    }
}
