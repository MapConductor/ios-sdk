import MapConductorCore
import UIKit
import XCTest

/**
 Markers land where their coordinates say they do.

 The draw was rewritten onto a bitmap context we own — 9x faster, and worth
 nothing if it puts the markers somewhere else, or upside down. Core Graphics
 has the origin at the bottom left and draws images bottom-up, so the rewrite
 carries two flips that have to cancel exactly.
 */
final class MarkerTilePlacementTests: XCTestCase {

    private let z = 12
    private let tileX = 3638
    private let tileY = 1612
    private let tileSize = 512

    /// Positions derived from the tile rather than written down, so the test
    /// cannot drift a marker into the neighbouring tile — which is what
    /// hand-computed coordinates did on the Android version of this test.
    private func atFraction(_ fx: Double, _ fy: Double) -> GeoPoint {
        let worldTiles = Double(1 << z)
        let longitude = (Double(tileX) + fx) / worldTiles * 360.0 - 180.0
        let n = Double.pi * (1.0 - 2.0 * (Double(tileY) + fy) / worldTiles)
        return GeoPoint(latitude: atan(sinh(n)) * 180 / .pi, longitude: longitude)
    }

    func testMarkersLandWhereTheirCoordinatesSay() throws {
        let positions = [atFraction(0.25, 0.25), atFraction(0.50, 0.60), atFraction(0.75, 0.40)]

        let manager = MarkerManager<Int>.defaultManager()
        for position in positions {
            manager.registerEntity(MarkerEntity<Int>(
                marker: nil, state: MarkerState(position: position),
                visible: true, isRendered: true, tiling: true
            ))
        }

        let renderer = MarkerTileRenderer<Int>(markerManager: manager, tileSize: tileSize)
        let png = try XCTUnwrap(
            renderer.renderTile(request: TileRequest(x: tileX, y: tileY, z: z)),
            "the tile was empty"
        )
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        let width = image.width
        var buffer = [UInt8](repeating: 0, count: width * width * 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer, width: width, height: width,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: width))

        func painted(_ x: Int, _ y: Int, radius: Int) -> Bool {
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let px = x + dx, py = y + dy
                    guard px >= 0, px < width, py >= 0, py < width else { continue }
                    if buffer[(py * width + px) * 4 + 3] != 0 { return true }
                }
            }
            return false
        }

        for (index, position) in positions.enumerated() {
            let worldTiles = Double(1 << z)
            let worldX = (position.longitude + 180) / 360 * worldTiles
            let latRad = position.latitude * .pi / 180
            let worldY = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * worldTiles
            let x = Int(((worldX - Double(tileX)) * Double(width)).rounded())
            let y = Int(((worldY - Double(tileY)) * Double(width)).rounded())
            // The default pin is anchored near its tip, so the icon body sits
            // above the coordinate; a small box around it is the honest test.
            XCTAssertTrue(painted(x, y, radius: 6), "marker \(index) missing at \(x),\(y)")
        }

        // Somewhere no marker is, so the tile is not simply filled in.
        XCTAssertFalse(painted(width / 2, 8, radius: 2), "unexpected paint near the top edge")

        // The icons are the right way up. The rewrite carries two vertical
        // flips that have to cancel, and a position check alone would pass with
        // both of them wrong: the default pin is anchored near its tip, so its
        // body sits above the coordinate. Counting which side is painted is
        // what actually distinguishes that from upside down.
        func paintedRows(around position: GeoPoint, above: Bool) -> Int {
            let worldTiles = Double(1 << z)
            let worldX = (position.longitude + 180) / 360 * worldTiles
            let latRad = position.latitude * .pi / 180
            let worldY = (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * worldTiles
            let x = Int(((worldX - Double(tileX)) * Double(width)).rounded())
            let y = Int(((worldY - Double(tileY)) * Double(width)).rounded())
            var count = 0
            for offset in 1...30 {
                let row = above ? y - offset : y + offset
                guard row >= 0, row < width else { continue }
                for dx in -20...20 where x + dx >= 0 && x + dx < width {
                    if buffer[(row * width + x + dx) * 4 + 3] != 0 { count += 1 }
                }
            }
            return count
        }

        let bodyAbove = paintedRows(around: positions[0], above: true)
        let bodyBelow = paintedRows(around: positions[0], above: false)
        XCTAssertGreaterThan(
            bodyAbove, bodyBelow,
            "the pin looks upside down: \(bodyAbove) painted above the anchor, \(bodyBelow) below"
        )
    }
}
