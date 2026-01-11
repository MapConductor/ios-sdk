import Foundation
import UIKit

public final class GroundImageTileProvider: TileProvider {
    public static let defaultTileSize: Int = 512

    public let tileSize: Int

    private let cacheLock = NSLock()
    private let cache: NSCache<NSString, CacheEntry>
    private var cacheEpoch: Int64 = 0

    private let overlayLock = NSLock()
    private var overlay: Overlay?

    public init(tileSize: Int = GroundImageTileProvider.defaultTileSize, cacheSizeKb: Int = 8 * 1024) {
        self.tileSize = tileSize
        let cache = NSCache<NSString, CacheEntry>()
        cache.totalCostLimit = cacheSizeKb * 1024
        self.cache = cache
    }

    public func update(state: GroundImageState, opacity: Double? = nil) {
        guard let sw = state.bounds.southWest, let ne = state.bounds.northEast else {
            overlayLock.lock()
            overlay = nil
            overlayLock.unlock()
            bumpCacheEpoch()
            return
        }
        let snapshotBounds = GeoRectBounds(
            southWest: GeoPoint.from(position: sw),
            northEast: GeoPoint.from(position: ne)
        )
        let resolvedOpacity = min(max(opacity ?? state.opacity, 0.0), 1.0)
        let image = state.image

        overlayLock.lock()
        overlay = Overlay(bounds: snapshotBounds, image: image, opacity: resolvedOpacity)
        overlayLock.unlock()

        bumpCacheEpoch()
    }

    public func renderTile(request: TileRequest) -> Data? {
        let epoch = cacheEpoch
        let key = "\(epoch):\(request.z)/\(request.x)/\(request.y)" as NSString

        cacheLock.lock()
        if let cached = cache.object(forKey: key) {
            cacheLock.unlock()
            return cached.isEmpty ? nil : cached.data
        }
        cacheLock.unlock()

        overlayLock.lock()
        let overlaySnapshot = overlay
        overlayLock.unlock()

        guard let overlaySnapshot, !overlaySnapshot.bounds.isEmpty else {
            putCache(key: key, data: nil)
            return nil
        }

        let bytes = renderTileInternal(overlay: overlaySnapshot, request: request)
        putCache(key: key, data: bytes)
        return bytes
    }

    private func bumpCacheEpoch() {
        cacheLock.lock()
        cacheEpoch += 1
        cache.removeAllObjects()
        cacheLock.unlock()
    }

    private func putCache(key: NSString, data: Data?) {
        let entry = CacheEntry(data: data)
        let cost = data?.count ?? 1
        cacheLock.lock()
        cache.setObject(entry, forKey: key, cost: cost)
        cacheLock.unlock()
    }

    private func renderTileInternal(overlay: Overlay, request: TileRequest) -> Data? {
        guard let sw = overlay.bounds.southWest, let ne = overlay.bounds.northEast else { return nil }

        let z = request.z
        let worldSize = Double(tileSize) * pow(2.0, Double(z))

        let north = ne.latitude
        let south = sw.latitude
        var west = sw.longitude
        var east = ne.longitude
        if west > east {
            east += 360.0
        }

        let overlayLeft = WebMercator.lonToPixelX(west, worldSize: worldSize)
        let overlayRight = WebMercator.lonToPixelX(east, worldSize: worldSize)
        let overlayTop = WebMercator.latToPixelY(north, worldSize: worldSize)
        let overlayBottom = WebMercator.latToPixelY(south, worldSize: worldSize)

        let overlayWidth = overlayRight - overlayLeft
        let overlayHeight = overlayBottom - overlayTop
        if overlayWidth <= 0.0 || overlayHeight <= 0.0 { return nil }

        let tileLeftBase = Double(request.x) * Double(tileSize)
        let tileRightBase = tileLeftBase + Double(tileSize)
        let tileTop = Double(request.y) * Double(tileSize)
        let tileBottom = tileTop + Double(tileSize)

        let tileLeft: Double
        if rectsIntersect(overlayLeft, overlayRight, tileLeftBase, tileRightBase) {
            tileLeft = tileLeftBase
        } else if rectsIntersect(overlayLeft, overlayRight, tileLeftBase + worldSize, tileRightBase + worldSize) {
            tileLeft = tileLeftBase + worldSize
        } else {
            return nil
        }
        let tileRight = tileLeft + Double(tileSize)

        let interLeft = max(overlayLeft, tileLeft)
        let interRight = min(overlayRight, tileRight)
        let interTop = max(overlayTop, tileTop)
        let interBottom = min(overlayBottom, tileBottom)
        if interLeft >= interRight || interTop >= interBottom { return nil }

        guard let cgImage = overlay.image.cgImage else { return nil }
        let imageWidth = Double(cgImage.width)
        let imageHeight = Double(cgImage.height)

        let srcLeft = floor(((interLeft - overlayLeft) / overlayWidth) * imageWidth).clamped(0.0, imageWidth)
        let srcRight = ceil(((interRight - overlayLeft) / overlayWidth) * imageWidth).clamped(0.0, imageWidth)
        let srcTop = floor(((interTop - overlayTop) / overlayHeight) * imageHeight).clamped(0.0, imageHeight)
        let srcBottom = ceil(((interBottom - overlayTop) / overlayHeight) * imageHeight).clamped(0.0, imageHeight)
        if srcLeft >= srcRight || srcTop >= srcBottom { return nil }

        let cropRect = CGRect(
            x: srcLeft,
            y: srcTop,
            width: srcRight - srcLeft,
            height: srcBottom - srcTop
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let destLeft = CGFloat(interLeft - tileLeft)
        let destRight = CGFloat(interRight - tileLeft)
        let destTop = CGFloat(interTop - tileTop)
        let destBottom = CGFloat(interBottom - tileTop)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize), format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: cropped, scale: 1.0, orientation: .up)
                .draw(
                    in: CGRect(x: destLeft, y: destTop, width: destRight - destLeft, height: destBottom - destTop),
                    blendMode: .normal,
                    alpha: overlay.opacity
                )
        }
        return image.pngData()
    }

    private func rectsIntersect(_ aLeft: Double, _ aRight: Double, _ bLeft: Double, _ bRight: Double) -> Bool {
        aLeft < bRight && aRight > bLeft
    }

    private final class CacheEntry {
        let data: Data?
        let isEmpty: Bool

        init(data: Data?) {
            self.data = data
            self.isEmpty = data == nil
        }
    }

    private struct Overlay {
        let bounds: GeoRectBounds
        let image: UIImage
        let opacity: Double
    }

    private enum WebMercator {
        private static let maxLat: Double = 85.05112878

        static func lonToPixelX(_ lon: Double, worldSize: Double) -> Double {
            ((lon + 180.0) / 360.0) * worldSize
        }

        static func latToPixelY(_ lat: Double, worldSize: Double) -> Double {
            let clamped = min(max(lat, -maxLat), maxLat)
            let sinLat = sin(clamped * Double.pi / 180.0)
            let y = 0.5 - log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * Double.pi)
            return y * worldSize
        }
    }
}

private extension Double {
    func clamped(_ minValue: Double, _ maxValue: Double) -> Double {
        min(max(self, minValue), maxValue)
    }
}
