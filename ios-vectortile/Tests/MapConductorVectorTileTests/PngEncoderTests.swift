import UIKit
import XCTest

import CTilePng
@testable import MapConductorCore

/**
 The Rust encoder against `UIImage.pngData()`, on marker-tile-shaped content.

 Reports rather than asserts a ratio: it measures the platform, and pinning a
 number would only fail the suite on different hardware.
 */
final class PngEncoderTests: XCTestCase {

    /// A tile the way the marker renderer leaves it: mostly transparent, with a
    /// few hundred anti-aliased icons on it. Circles, not rectangles — hard
    /// edges compress unlike anything real, which already sent one filter
    /// decision the wrong way in this project.
    private func markerTile(size: CGFloat, icons: Int, iconPx: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        var seed: UInt64 = 12345
        func next(_ bound: UInt64) -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % bound)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { context in
                for _ in 0..<icons {
                    let x = next(UInt64(size - iconPx))
                    let y = next(UInt64(size - iconPx))
                    UIColor(red: 0.16, green: 0.35, blue: 0.78, alpha: 0.9).setFill()
                    context.cgContext.fillEllipse(
                        in: CGRect(x: x, y: y, width: iconPx, height: iconPx)
                    )
                }
            }
    }

    func testRustEncoderAgainstThePlatform() throws {
        let tile = markerTile(size: 1024, icons: 600, iconPx: 64)

        func median(_ samples: [Double]) -> Double { samples.sorted()[samples.count / 2] }

        var platformBytes = 0
        let platform = median((0..<5).map { _ in
            let started = CFAbsoluteTimeGetCurrent()
            let data = tile.pngData()
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            platformBytes = data?.count ?? 0
            return elapsed
        })

        var rustBytes = 0
        let rust = median((0..<5).map { _ in
            let started = CFAbsoluteTimeGetCurrent()
            let data = NativePngEncoder.encode(tile)
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            rustBytes = data?.count ?? 0
            return elapsed
        })

        print(String(
            format: "IOS_PNG platform=%.1fms/%dB rust=%.1fms/%dB speed=%.1fx size=%.1fx",
            platform, platformBytes, rust, rustBytes,
            platform / rust, Double(rustBytes) / Double(platformBytes)
        ))
        XCTAssertGreaterThan(rustBytes, 0, "the native encoder produced nothing")
    }

    /// The encoder must not change what the tile looks like.
    func testRustOutputMatchesThePlatformVisually() throws {
        let tile = markerTile(size: 256, icons: 40, iconPx: 40)
        let rust = try XCTUnwrap(NativePngEncoder.encode(tile))
        let platform = try XCTUnwrap(tile.pngData())

        func pixels(_ data: Data) throws -> [UInt8] {
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            var buffer = [UInt8](repeating: 0, count: 256 * 256 * 4)
            let context = try XCTUnwrap(CGContext(
                data: &buffer, width: 256, height: 256,
                bitsPerComponent: 8, bytesPerRow: 256 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
            return buffer
        }

        let a = try pixels(rust)
        let b = try pixels(platform)
        var worst = 0
        for index in 0..<a.count {
            worst = max(worst, abs(Int(a[index]) - Int(b[index])))
        }
        // A couple of levels is the round trip through premultiplied storage,
        // which both paths make; anything more would be the un-premultiply
        // getting it wrong.
        print("IOS_PNG_DIFF worst channel delta \(worst)")
        XCTAssertLessThanOrEqual(worst, 2, "the native encoder changed the image")
    }
    /// How much of the native path is the encoder, and how much is getting the
    /// pixels out of a UIImage in the first place.
    @MainActor
    func testWhereTheNativePathSpendsItsTime() throws {
        let size = 1024
        let tile = markerTile(size: CGFloat(size), icons: 600, iconPx: 64)
        let cgImage = try XCTUnwrap(tile.cgImage)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        func median(_ samples: [Double]) -> Double { samples.sorted()[samples.count / 2] }

        let extract = median((0..<5).map { _ in
            let started = CFAbsoluteTimeGetCurrent()
            pixels.withUnsafeMutableBytes { raw in
                let context = CGContext(
                    data: raw.baseAddress, width: size, height: size,
                    bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
            return (CFAbsoluteTimeGetCurrent() - started) * 1000
        })

        // Encode only, on pixels already in hand.
        let encodeOnly = median((0..<5).map { _ in
            var scratch = pixels
            var outPointer: UnsafeMutablePointer<UInt8>?
            var outLength = 0
            let started = CFAbsoluteTimeGetCurrent()
            _ = scratch.withUnsafeMutableBufferPointer { buffer in
                tile_png_encode(buffer.baseAddress, UInt32(size), UInt32(size), 1,
                                &outPointer, &outLength)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
            if let outPointer { tile_png_buffer_free(outPointer, outLength) }
            return elapsed
        })

        print(String(format: "IOS_PNG_SPLIT extract=%.1fms encodeOnly=%.1fms", extract, encodeOnly))
        XCTAssertGreaterThan(encodeOnly, 0)
    }

    /// What share of a real marker tile the encoder actually is.
    ///
    /// The encoder being 1.7x faster only matters in proportion to how much of
    /// a tile it accounts for, and nothing had measured that on iOS.
    @MainActor
    func testEncoderShareOfARealMarkerTile() throws {
        for markerCount in [2_000, 20_000] {
            let manager = MarkerManager<Int>.defaultManager()
            var seed: UInt64 = 12345
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            for _ in 0..<markerCount {
                let position = GeoPoint(latitude: 35.5 + next() * 0.4,
                                        longitude: 139.5 + next() * 0.5)
                manager.registerEntity(MarkerEntity<Int>(
                    marker: nil, state: MarkerState(position: position),
                    visible: true, isRendered: true, tiling: true
                ))
            }

            for (z, x, y) in [(12, 3638, 1612), (6, 56, 25)] {
                func median(_ samples: [Double]) -> Double { samples.sorted()[samples.count / 2] }
                // A fresh renderer per round: its cache would answer every call
                // after the first, which is not what this measures.
                let samples = (0..<3).map { _ -> Double in
                    let renderer = MarkerTileRenderer<Int>(
                        markerManager: manager, tileSize: 512
                    )
                    let started = CFAbsoluteTimeGetCurrent()
                    _ = renderer.renderTile(request: TileRequest(x: x, y: y, z: z))
                    return (CFAbsoluteTimeGetCurrent() - started) * 1000
                }
                print(String(format: "IOS_MARKERTILE n=%d z=%d render=%.1fms",
                             markerCount, z, median(samples)))
            }
        }
    }

}
