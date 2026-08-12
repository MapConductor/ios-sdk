import CoreGraphics
import Foundation
import UIKit

/// フィーチャーを `CGContext` へ描く部分。
///
/// 世界座標からタイル内ピクセルへの変換は呼び出し側から関数で受け取る
/// （タイルごとに原点と縮尺が変わるため）。
///
/// android-sdk の android-kml の `KMLTilePainter.kt` と同じ描き方。
enum KMLTilePainter {
    /// - Returns: 何か描いたとき true。
    static func drawFeature(
        _ ctx: CGContext,
        feature: RenderFeature,
        toPixelX: (Double) -> CGFloat,
        toPixelY: (Double) -> CGFloat
    ) -> Bool {
        drawGeometry(ctx, geometry: feature.worldGeometry, feature: feature, toPixelX: toPixelX, toPixelY: toPixelY)
    }

    private static func drawGeometry(
        _ ctx: CGContext,
        geometry: WorldGeometry,
        feature: RenderFeature,
        toPixelX: (Double) -> CGFloat,
        toPixelY: (Double) -> CGFloat
    ) -> Bool {
        switch geometry {
        case .point(let wx, let wy):
            drawPoint(ctx, feature: feature, px: toPixelX(wx), py: toPixelY(wy))
            return true

        case .points(let pts):
            guard !pts.isEmpty else { return false }
            for pt in pts {
                drawPoint(ctx, feature: feature, px: toPixelX(pt.wx), py: toPixelY(pt.wy))
            }
            return true

        case .line(let rings):
            let path = CGMutablePath()
            for ring in rings {
                guard ring.count >= 2 else { continue }
                path.move(to: CGPoint(x: toPixelX(ring[0].wx), y: toPixelY(ring[0].wy)))
                for i in 1..<ring.count {
                    path.addLine(to: CGPoint(x: toPixelX(ring[i].wx), y: toPixelY(ring[i].wy)))
                }
            }
            guard !path.isEmpty else { return false }
            ctx.addPath(path)
            ctx.setStrokeColor(feature.strokeColor.cgColor)
            ctx.setLineWidth(feature.strokeWidth)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.strokePath()
            return true

        case .polygon(let rings):
            let path = CGMutablePath()
            for ring in rings {
                guard ring.count >= 3 else { continue }
                path.move(to: CGPoint(x: toPixelX(ring[0].wx), y: toPixelY(ring[0].wy)))
                for i in 1..<ring.count {
                    path.addLine(to: CGPoint(x: toPixelX(ring[i].wx), y: toPixelY(ring[i].wy)))
                }
                path.closeSubpath()
            }
            guard !path.isEmpty else { return false }
            ctx.addPath(path)
            ctx.setFillColor(feature.fillColor.cgColor)
            // 穴を扱うため even-odd で塗る（外環と内環を同じパスに入れてある）。
            ctx.fillPath(using: .evenOdd)
            ctx.addPath(path)
            ctx.setStrokeColor(feature.strokeColor.cgColor)
            ctx.setLineWidth(feature.strokeWidth)
            ctx.strokePath()
            return true

        case .collection(let parts):
            return parts.reduce(false) {
                drawGeometry(ctx, geometry: $1, feature: feature, toPixelX: toPixelX, toPixelY: toPixelY) || $0
            }

        case .empty:
            return false
        }
    }

    private static func drawPoint(_ ctx: CGContext, feature: RenderFeature, px: CGFloat, py: CGFloat) {
        let r = feature.pointRadius
        let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
        ctx.setFillColor(feature.fillColor.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(feature.strokeColor.cgColor)
        ctx.setLineWidth(feature.strokeWidth)
        ctx.strokeEllipse(in: rect)
    }
}
