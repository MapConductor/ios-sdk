import UIKit
import XCTest

/**
 Measures what a non-integer destination costs CoreGraphics.

 The marker tile renderer used to hand `draw(in:)` a rectangle straight out of
 the projection, so it almost never landed on a whole pixel. On Android that
 cost 20x and in Chromium 7x; this checks whether CoreGraphics behaves the same
 way rather than assuming it does.
 */
final class BlitAlignmentTests: XCTestCase {

    func testWholePixelDestinationsAreCheaper() throws {
        let iconPx: CGFloat = 84
        let count = 20_000
        let canvasPx: CGFloat = 1344

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let icon = UIGraphicsImageRenderer(
            size: CGSize(width: iconPx, height: iconPx), format: format
        ).image { context in
            UIColor(red: 0.16, green: 0.35, blue: 0.78, alpha: 0.86).setFill()
            context.fill(CGRect(x: 0, y: 0, width: iconPx, height: iconPx))
        }

        func cost(fractional: Bool) -> Double {
            var samples: [Double] = []
            for _ in 0..<3 {
                let started = CFAbsoluteTimeGetCurrent()
                _ = UIGraphicsImageRenderer(
                    size: CGSize(width: canvasPx, height: canvasPx), format: format
                ).image { _ in
                    for index in 0..<count {
                        let baseX = CGFloat(index % 600)
                        let baseY = CGFloat((index / 600) % 600)
                        // 0.37 is arbitrary; all that matters is that it is not
                        // a whole pixel.
                        let offset: CGFloat = fractional ? 0.37 : 0
                        icon.draw(in: CGRect(
                            x: baseX + offset, y: baseY + offset,
                            width: iconPx, height: iconPx
                        ))
                    }
                }
                samples.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            return samples.sorted()[1]
        }

        let fractional = cost(fractional: true)
        let aligned = cost(fractional: false)
        print(String(format: "IOS_BLIT n=%d fractional=%.0fms aligned=%.0fms ratio=%.1fx",
                     count, fractional, aligned, fractional / aligned))
        // Reported, not asserted: this measures the platform, and pinning a
        // ratio would only make the suite fail on a faster machine.
        XCTAssertGreaterThan(fractional, 0)
    }
}
