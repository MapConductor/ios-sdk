import CoreGraphics
import MapConductorCore
import UIKit
import XCTest

import MapConductorVectorTile

/**
 Exercises the Metal path against the CPU one.

 The interesting failure here is not a crash, it is a silent fallback: a
 provider that quietly renders on the CPU looks exactly like a working GPU
 provider from the outside, so these tests check the counters as well as the
 pixels.
 */
final class MetalRenderModeTests: XCTestCase {

    private var styleJSON: String!
    private var tileData: Data!
    private let tileSize = 512

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

    private func provider(_ mode: VectorTileProvider.RenderMode) throws -> VectorTileProvider {
        try VectorTileProvider(
            styleJSON: styleJSON, tileSize: tileSize, renderMode: mode
        ) { [tileData] _ in tileData }
    }

    func testGpuModeProducesAPng() throws {
        let provider = try provider(.gpu)
        defer { provider.close() }

        let png = try XCTUnwrap(provider.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "not a PNG")

        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(Int(image.size.width), tileSize)
        XCTAssertEqual(Int(image.size.height), tileSize)
    }

    func testGpuModeActuallyDrawsOnTheGpu() throws {
        let provider = try provider(.gpu)
        defer { provider.close() }

        for x in 0..<2 {
            XCTAssertNotNil(provider.renderTile(request: TileRequest(x: x, y: 0, z: 1)))
        }
        XCTAssertEqual(provider.gpuRenders, 2)
        // The claim this test exists to defend. Without it the whole suite
        // passes while every tile silently falls back to tiny-skia.
        XCTAssertEqual(provider.gpuFallbacks, 0, "GPU tiles fell back to the CPU")
    }

    func testCpuModeNeverTouchesTheGpu() throws {
        let provider = try provider(.cpu)
        defer { provider.close() }

        XCTAssertNotNil(provider.renderTile(request: TileRequest(x: 0, y: 0, z: 0)))
        XCTAssertEqual(provider.renderMode, .cpu)
        XCTAssertEqual(provider.gpuRenders, 0)
    }

    func testGpuAndCpuAgreeOnWhatTheTileLooksLike() throws {
        let gpuProvider = try provider(.gpu)
        let cpuProvider = try provider(.cpu)
        defer { gpuProvider.close(); cpuProvider.close() }

        let request = TileRequest(x: 0, y: 0, z: 0)
        let gpu = try pixels(XCTUnwrap(gpuProvider.renderTile(request: request)))
        let cpu = try pixels(XCTUnwrap(cpuProvider.renderTile(request: request)))

        // Compared as 8x8 block averages, not pixel by pixel. The two
        // rasterisers genuinely differ on edges — MSAA against analytic
        // coverage — and this test tile is a whole world at z0, which is almost
        // entirely coastline: about 3% of its pixels sit on an edge, while a
        // normal street tile measures well under one. Averaging asks the
        // question the claim actually makes, that no *region* disagrees.
        let block = 8
        let blocks = tileSize / block
        var differingBlocks = 0
        var worstBlock = 0

        for blockY in 0..<blocks {
            for blockX in 0..<blocks {
                var worstChannel = 0
                for channel in 0..<3 {
                    var gpuSum = 0
                    var cpuSum = 0
                    for y in 0..<block {
                        let row = (blockY * block + y) * tileSize * 4
                        for x in 0..<block {
                            let index = row + (blockX * block + x) * 4 + channel
                            gpuSum += Int(gpu[index])
                            cpuSum += Int(cpu[index])
                        }
                    }
                    let pixelsPerBlock = block * block
                    worstChannel = max(worstChannel, abs(gpuSum / pixelsPerBlock - cpuSum / pixelsPerBlock))
                }
                if worstChannel > 24 { differingBlocks += 1 }
                worstBlock = max(worstBlock, worstChannel)
            }
        }

        let percent = Double(differingBlocks) * 100 / Double(blocks * blocks)
        print(String(format: "GPU_VS_CPU_BLOCKS=%.2f%% worst=%d", percent, worstBlock))
        XCTAssertLessThan(
            percent, 1.0,
            String(format: "%.2f%% of 8x8 blocks disagree (worst channel delta %d)", percent, worstBlock)
        )
    }

    func testGpuIsNotSlowerThanTheCpu() throws {
        let gpuProvider = try provider(.gpu)
        let cpuProvider = try provider(.cpu)
        defer { gpuProvider.close(); cpuProvider.close() }

        func cost(_ provider: VectorTileProvider) -> Double {
            // One warm-up: the first tile pays for pipeline compilation and
            // texture allocation, which is not what this measures.
            _ = provider.renderTile(request: TileRequest(x: 0, y: 0, z: 0))
            let started = CFAbsoluteTimeGetCurrent()
            for _ in 0..<3 {
                _ = provider.renderTile(request: TileRequest(x: 0, y: 0, z: 0))
            }
            return (CFAbsoluteTimeGetCurrent() - started) * 1000 / 3
        }

        let gpu = cost(gpuProvider)
        let cpu = cost(cpuProvider)
        print(String(format: "MODE_COST gpu=%.1fms cpu=%.1fms", gpu, cpu))
        // Deliberately loose. The point is to catch a regression that makes the
        // GPU path pointless, not to pin a number that varies with thermal
        // state — device timings swing by 3x when the chip is hot.
        XCTAssertLessThan(gpu, cpu * 1.5)
    }

    /// Decodes PNG bytes to straight-alpha RGBA.
    private func pixels(_ png: Data) throws -> [UInt8] {
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        var buffer = [UInt8](repeating: 0, count: tileSize * tileSize * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &buffer,
                width: tileSize, height: tileSize,
                bitsPerComponent: 8, bytesPerRow: tileSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        // Draw onto opaque white so premultiplication cannot change the
        // comparison: both renders land on the same ground.
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        context.draw(image, in: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
        return buffer
    }
}
