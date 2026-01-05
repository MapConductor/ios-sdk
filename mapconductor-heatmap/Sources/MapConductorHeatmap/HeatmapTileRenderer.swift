import Foundation
import Accelerate
import MapConductorCore
import MapConductorTileServer
import UIKit

public final class HeatmapTileRenderer: TileProvider {
    public let tileSize: Int

    private let cacheLock = NSLock()
    private let cache = NSCache<NSString, NSData>()
    private let emptyTileMarker = NSData(bytes: [0], length: 1)
    private var kernelCache: [Int: [Double]] = [:]
    private let kernelLock = NSLock()

    private let stateLock = NSLock()
    private var cameraZoom: Double?
    private var cameraZoomKey: Int?
    private var state: TileState

    public init(tileSize: Int = HeatmapTileRenderer.defaultTileSize, cacheSizeKb: Int = HeatmapTileRenderer.defaultCacheSizeKb) {
        self.tileSize = tileSize
        self.state = TileState(
            points: [],
            bounds: nil,
            radiusPx: HeatmapTileRenderer.defaultRadiusPx,
            colorMap: Array(repeating: HeatmapColor.argb(0, 0, 0, 0), count: HeatmapTileRenderer.colorMapSize),
            maxIntensities: Array(repeating: 0.0, count: HeatmapTileRenderer.maxZoomLevel)
        )
        cache.totalCostLimit = cacheSizeKb * 1024
    }

    public func update(points: [HeatmapPoint], radiusPx: Int, gradient: HeatmapGradient, maxIntensity: Double?) {
        let safeRadius = max(1, radiusPx)
        let weightedPoints = buildWeightedPoints(points)
        let bounds = weightedPoints.isEmpty ? nil : calculateBounds(weightedPoints)
        let colorMap = buildColorMap(gradient)
        let maxIntensities: [Double]
        if let bounds {
            maxIntensities = getMaxIntensities(points: weightedPoints, bounds: bounds, radius: safeRadius, customMaxIntensity: maxIntensity)
        } else {
            maxIntensities = Array(repeating: 0.0, count: HeatmapTileRenderer.maxZoomLevel)
        }
        let nextState = TileState(
            points: weightedPoints,
            bounds: bounds,
            radiusPx: safeRadius,
            colorMap: colorMap,
            maxIntensities: maxIntensities
        )
        stateLock.lock()
        state = nextState
        stateLock.unlock()
        clearCache()
    }

    public func updateCameraZoom(_ zoom: Double) {
        let nextKey = Int((zoom * 100.0).rounded())
        var shouldClearCache = false
        stateLock.lock()
        let previousKey = cameraZoomKey
        cameraZoom = zoom
        if previousKey != nextKey {
            cameraZoomKey = nextKey
            shouldClearCache = true
        }
        stateLock.unlock()
        if shouldClearCache {
            clearCache()
        }
    }

    public func resetCameraZoom() {
        var shouldClearCache = false
        stateLock.lock()
        if cameraZoomKey != nil {
            shouldClearCache = true
        }
        cameraZoom = nil
        cameraZoomKey = nil
        stateLock.unlock()
        if shouldClearCache {
            clearCache()
        }
    }

    public func renderTile(request: TileRequest) -> Data? {
        let snapshot: TileState
        let cameraZoomSnapshot: Double?
        let cameraZoomKeySnapshot: Int
        stateLock.lock()
        snapshot = state
        cameraZoomSnapshot = cameraZoom
        cameraZoomKeySnapshot = cameraZoomKey ?? -1
        stateLock.unlock()

        let key = "\(cameraZoomKeySnapshot)/\(request.z)/\(request.x)/\(request.y)" as NSString
        cacheLock.lock()
        if let cached = cache.object(forKey: key) {
            cacheLock.unlock()
            return cached === emptyTileMarker ? nil : cached as Data
        }
        cacheLock.unlock()

        let bytes = renderTileInternal(request: request, tileState: snapshot, cameraZoom: cameraZoomSnapshot)
        cacheLock.lock()
        cache.setObject(bytes == nil ? emptyTileMarker : (bytes! as NSData), forKey: key, cost: bytes?.count ?? 1)
        cacheLock.unlock()
        return bytes
    }

    private func renderTileInternal(request: TileRequest, tileState: TileState, cameraZoom: Double?) -> Data? {
        guard let bounds = tileState.bounds else { return emptyTileData }
        if tileState.points.isEmpty { return emptyTileData }

        let zoom = Double(request.z)
        let zoomScale = pow(2.0, (cameraZoom ?? zoom) - zoom)
        let radiusRaw = Int((Double(tileState.radiusPx) / zoomScale).rounded())
        // Clamp to avoid excessive allocations when camera zoom differs greatly from tile zoom.
        let radius = max(1, min(radiusRaw, tileSize))
        let kernel = resolveKernel(radius)
        let tileWidth = HeatmapTileRenderer.worldWidth / pow(2.0, zoom)
        let padding = tileWidth * Double(radius) / Double(tileSize)
        let tileWidthPadded = tileWidth + 2.0 * padding
        let gridDim = tileSize + radius * 2
        let bucketWidth = tileWidthPadded / Double(gridDim)

        let minX = Double(request.x) * tileWidth - padding
        let maxX = Double(request.x + 1) * tileWidth + padding
        let minY = Double(request.y) * tileWidth - padding
        let maxY = Double(request.y + 1) * tileWidth + padding

        let tileBounds = Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        let paddedBounds = Bounds(
            minX: bounds.minX - padding,
            maxX: bounds.maxX + padding,
            minY: bounds.minY - padding,
            maxY: bounds.maxY + padding
        )
        if !tileBounds.intersects(paddedBounds) { return emptyTileData }

        var intensity = Array(repeating: 0.0, count: gridDim * gridDim)
        var hasPoints = false

        var overlapMinX = 0.0
        var overlapMaxX = 0.0
        var xOffset = 0.0
        if minX < 0.0 {
            overlapMinX = minX + HeatmapTileRenderer.worldWidth
            overlapMaxX = HeatmapTileRenderer.worldWidth
            xOffset = -HeatmapTileRenderer.worldWidth
        } else if maxX > HeatmapTileRenderer.worldWidth {
            overlapMinX = 0.0
            overlapMaxX = maxX - HeatmapTileRenderer.worldWidth
            xOffset = HeatmapTileRenderer.worldWidth
        }

        func addPoint(worldX: Double, worldY: Double, weight: Double) {
            let bucketX = Int((worldX - minX) / bucketWidth)
            let bucketY = Int((worldY - minY) / bucketWidth)
            if bucketX < 0 || bucketX >= gridDim || bucketY < 0 || bucketY >= gridDim {
                return
            }
            intensity[bucketX * gridDim + bucketY] += weight
        }

        for point in tileState.points {
            if point.y < minY || point.y > maxY { continue }
            var added = false
            if point.x >= minX && point.x <= maxX {
                addPoint(worldX: point.x, worldY: point.y, weight: point.intensity)
                added = true
            }
            if xOffset != 0.0 && point.x >= overlapMinX && point.x <= overlapMaxX {
                addPoint(worldX: point.x + xOffset, worldY: point.y, weight: point.intensity)
                added = true
            }
            if added { hasPoints = true }
        }

        if !hasPoints { return emptyTileData }

        let convolved = convolve(grid: intensity, dimOld: gridDim, kernel: kernel)
        let zoomIndex = Int(cameraZoom ?? zoom)
        let clampedIndex = max(0, min(zoomIndex, tileState.maxIntensities.count - 1))
        let maxIntensity = tileState.maxIntensities[clampedIndex]
        if maxIntensity <= 0.0 { return emptyTileData }

        return colorize(grid: convolved.grid, dim: convolved.dim, colorMap: tileState.colorMap, max: maxIntensity) ?? emptyTileData
    }

    private func buildWeightedPoints(_ points: [HeatmapPoint]) -> [WeightedPoint] {
        if points.isEmpty { return [] }
        var weighted: [WeightedPoint] = []
        weighted.reserveCapacity(points.count)
        for point in points {
            let weight: Double
            if point.weight.isNaN || point.weight < 0.0 {
                weight = HeatmapTileRenderer.defaultIntensity
            } else {
                weight = point.weight
            }
            let world = toWorldPoint(point.position)
            weighted.append(WeightedPoint(x: world.x, y: world.y, intensity: weight))
        }
        return weighted
    }

    private func toWorldPoint(_ position: GeoPoint) -> WorldPoint {
        let x = position.longitude / 360.0 + 0.5
        let siny = sin(position.latitude * Double.pi / 180.0)
        let clamped = max(-0.9999, min(0.9999, siny))
        let y = 0.5 * log((1 + clamped) / (1 - clamped)) / -(2 * Double.pi) + 0.5
        return WorldPoint(x: x, y: y)
    }

    private func calculateBounds(_ points: [WeightedPoint]) -> Bounds {
        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            if point.x < minX { minX = point.x }
            if point.x > maxX { maxX = point.x }
            if point.y < minY { minY = point.y }
            if point.y > maxY { maxY = point.y }
        }
        return Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private func resolveKernel(_ radius: Int) -> [Double] {
        if radius <= 0 { return [1.0] }
        kernelLock.lock()
        if let cached = kernelCache[radius] {
            kernelLock.unlock()
            return cached
        }
        let built = generateKernel(radius: radius, sd: Double(radius) / 3.0)
        kernelCache[radius] = built
        kernelLock.unlock()
        return built
    }

    private func generateKernel(radius: Int, sd: Double) -> [Double] {
        let size = radius * 2 + 1
        var kernel = Array(repeating: 0.0, count: size)
        for i in -radius...radius {
            let value = exp(-Double(i * i) / (2 * sd * sd))
            kernel[i + radius] = value
        }
        return kernel
    }

    private func convolve(grid: [Double], dimOld: Int, kernel: [Double]) -> (grid: [Double], dim: Int) {
        if useAccelerateConvolution {
            if let result = convolveAccelerate(grid: grid, dimOld: dimOld, kernel: kernel) {
                return result
            }
        }
        let radius = kernel.count / 2
        let dim = dimOld - 2 * radius
        let lowerLimit = radius
        let upperLimit = radius + dim - 1

        var intermediate = Array(repeating: 0.0, count: dimOld * dimOld)
        for x in 0..<dimOld {
            let base = x * dimOld
            for y in 0..<dimOld {
                let value = grid[base + y]
                if value == 0.0 { continue }
                let xUpperLimit = min(upperLimit, x + radius) + 1
                let initial = max(lowerLimit, x - radius)
                for x2 in initial..<xUpperLimit {
                    intermediate[x2 * dimOld + y] += value * kernel[x2 - (x - radius)]
                }
            }
        }

        var output = Array(repeating: 0.0, count: dim * dim)
        for x in lowerLimit...upperLimit {
            let base = x * dimOld
            for y in 0..<dimOld {
                let value = intermediate[base + y]
                if value == 0.0 { continue }
                let yUpperLimit = min(upperLimit, y + radius) + 1
                let initial = max(lowerLimit, y - radius)
                for y2 in initial..<yUpperLimit {
                    output[(x - radius) * dim + (y2 - radius)] += value * kernel[y2 - (y - radius)]
                }
            }
        }
        return (output, dim)
    }

    private func convolveAccelerate(grid: [Double], dimOld: Int, kernel: [Double]) -> (grid: [Double], dim: Int)? {
        let radius = kernel.count / 2
        let dim = dimOld - 2 * radius
        guard dimOld > 0, dim > 0 else { return nil }

        convolutionLock.lock()
        ensureConvolutionBuffers(dimOld: dimOld, dim: dim)

        grid.withUnsafeBufferPointer { gridPtr in
            vDSPIntermediateBuffer.withUnsafeMutableBufferPointer { interPtr in
                for y in 0..<dimOld {
                    let inputStart = gridPtr.baseAddress! + y
                    let outputStart = interPtr.baseAddress! + y
                    vDSP_convD(
                        inputStart,
                        vDSP_Stride(dimOld),
                        kernel,
                        1,
                        outputStart,
                        vDSP_Stride(dimOld),
                        vDSP_Length(dim),
                        vDSP_Length(kernel.count)
                    )
                }
            }
        }

        vDSPIntermediateBuffer.withUnsafeBufferPointer { interPtr in
            vDSPOutputBuffer.withUnsafeMutableBufferPointer { outPtr in
                for x in 0..<dim {
                    let inputStart = interPtr.baseAddress! + (x * dimOld)
                    let outputStart = outPtr.baseAddress! + (x * dim)
                    vDSP_convD(
                        inputStart,
                        1,
                        kernel,
                        1,
                        outputStart,
                        1,
                        vDSP_Length(dim),
                        vDSP_Length(kernel.count)
                    )
                }
            }
        }

        let output = vDSPOutputBuffer
        convolutionLock.unlock()

        return (output, dim)
    }

    private func colorize(grid: [Double], dim: Int, colorMap: [UInt32], max: Double) -> Data? {
        let maxColor = colorMap[colorMap.count - 1]
        let colorMapScaling = Double(colorMap.count - 1) / max
        var pixels = [UInt8](repeating: 0, count: dim * dim * 4)

        for i in 0..<dim {
            for j in 0..<dim {
                let value = grid[j * dim + i]
                let index = (i * dim + j) * 4
                if value != 0.0 {
                    let colorIndex = Int(value * colorMapScaling)
                    let color = colorIndex < colorMap.count ? colorMap[colorIndex] : maxColor
                    let alpha = HeatmapColor.alpha(color)
                    let premultipliedR = HeatmapColor.red(color) * alpha / 255
                    let premultipliedG = HeatmapColor.green(color) * alpha / 255
                    let premultipliedB = HeatmapColor.blue(color) * alpha / 255
                    pixels[index] = UInt8(premultipliedR)
                    pixels[index + 1] = UInt8(premultipliedG)
                    pixels[index + 2] = UInt8(premultipliedB)
                    pixels[index + 3] = UInt8(alpha)
                } else {
                    pixels[index + 3] = 0
                }
            }
        }

        let data = Data(pixels)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let image = CGImage(
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dim * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: image).pngData()
    }

    private func buildColorMap(_ gradient: HeatmapGradient) -> [UInt32] {
        let colors = gradient.colors()
        let startPoints = gradient.startPoints()
        return generateColorMap(colors: colors, startPoints: startPoints, mapSize: HeatmapTileRenderer.colorMapSize)
    }

    private func generateColorMap(colors: [UInt32], startPoints: [Float], mapSize: Int) -> [UInt32] {
        precondition(!colors.isEmpty, "Heatmap gradient requires at least one color.")
        var colorIntervals: [Int: ColorInterval] = [:]

        if startPoints[0] != 0 {
            let initialColor = HeatmapColor.argb(0, HeatmapColor.red(colors[0]), HeatmapColor.green(colors[0]), HeatmapColor.blue(colors[0]))
            colorIntervals[0] = ColorInterval(color1: initialColor, color2: colors[0], duration: Double(mapSize) * Double(startPoints[0]))
        }

        if colors.count > 1 {
            for i in 1..<colors.count {
                colorIntervals[Int(Double(mapSize) * Double(startPoints[i - 1]))] = ColorInterval(
                    color1: colors[i - 1],
                    color2: colors[i],
                    duration: Double(mapSize) * Double(startPoints[i] - startPoints[i - 1])
                )
            }
        }

        if let last = startPoints.last, last != 1.0 {
            let index = startPoints.count - 1
            colorIntervals[Int(Double(mapSize) * Double(last))] = ColorInterval(
                color1: colors[index],
                color2: colors[index],
                duration: Double(mapSize) * Double(1.0 - last)
            )
        }

        var colorMap = Array(repeating: colors[0], count: mapSize)
        var interval = colorIntervals[0] ?? ColorInterval(color1: colors[0], color2: colors[0], duration: 1.0)
        var start = 0
        for i in 0..<mapSize {
            if let next = colorIntervals[i] {
                interval = next
                start = i
            }
            let ratio = interval.duration == 0 ? 0.0 : Double(i - start) / interval.duration
            colorMap[i] = interpolateColor(color1: interval.color1, color2: interval.color2, ratio: ratio)
        }
        return colorMap
    }

    private func interpolateColor(color1: UInt32, color2: UInt32, ratio: Double) -> UInt32 {
        let clamped = max(0.0, min(1.0, ratio))
        let alpha = Int((Double(HeatmapColor.alpha(color2) - HeatmapColor.alpha(color1)) * clamped + Double(HeatmapColor.alpha(color1))).rounded())
        var hsv1 = HeatmapColor.hsvComponents(color1)
        var hsv2 = HeatmapColor.hsvComponents(color2)

        if hsv1.h - hsv2.h > 180 {
            hsv2.h += 360
        } else if hsv2.h - hsv1.h > 180 {
            hsv1.h += 360
        }

        let h = (hsv2.h - hsv1.h) * clamped + hsv1.h
        let s = (hsv2.s - hsv1.s) * clamped + hsv1.s
        let v = (hsv2.v - hsv1.v) * clamped + hsv1.v

        return HeatmapColor.colorFromHSV(alpha: alpha, h: h, s: s, v: v)
    }

    private func getMaxIntensities(
        points: [WeightedPoint],
        bounds: Bounds,
        radius: Int,
        customMaxIntensity: Double?
    ) -> [Double] {
        var maxIntensityArray = Array(repeating: 0.0, count: HeatmapTileRenderer.maxZoomLevel)
        if let customMaxIntensity, customMaxIntensity != 0.0 {
            for i in 0..<maxIntensityArray.count {
                maxIntensityArray[i] = customMaxIntensity
            }
            return maxIntensityArray
        }

        for i in HeatmapTileRenderer.defaultMinZoom..<HeatmapTileRenderer.defaultMaxZoom {
            let screenDim = Int((HeatmapTileRenderer.screenSize * pow(2.0, Double(i - 3))).rounded())
            maxIntensityArray[i] = getMaxValue(points: points, bounds: bounds, radius: radius, screenDim: screenDim)
            if i == HeatmapTileRenderer.defaultMinZoom {
                for j in 0..<i {
                    maxIntensityArray[j] = maxIntensityArray[i]
                }
            }
        }

        if HeatmapTileRenderer.defaultMaxZoom < HeatmapTileRenderer.maxZoomLevel {
            for i in HeatmapTileRenderer.defaultMaxZoom..<HeatmapTileRenderer.maxZoomLevel {
                maxIntensityArray[i] = maxIntensityArray[HeatmapTileRenderer.defaultMaxZoom - 1]
            }
        }

        return maxIntensityArray
    }

    private func getMaxValue(points: [WeightedPoint], bounds: Bounds, radius: Int, screenDim: Int) -> Double {
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY
        let boundsDim = max(maxX - minX, maxY - minY)
        if boundsDim == 0.0 {
            return points.map { $0.intensity }.max() ?? 0.0
        }
        let nBuckets = max(1, Int(Double(screenDim) / (2.0 * Double(radius)) + 0.5))
        let scale = Double(nBuckets) / boundsDim
        var buckets: [Int: [Int: Double]] = [:]
        var maxValue = 0.0
        for point in points {
            let xBucket = Int((point.x - minX) * scale)
            let yBucket = Int((point.y - minY) * scale)
            var column = buckets[xBucket] ?? [:]
            let nextValue = (column[yBucket] ?? 0.0) + point.intensity
            column[yBucket] = nextValue
            buckets[xBucket] = column
            if nextValue > maxValue {
                maxValue = nextValue
            }
        }
        return maxValue
    }

    private func clearCache() {
        cacheLock.lock()
        cache.removeAllObjects()
        cacheLock.unlock()
    }

    private static func makeEmptyTile(size: Int) -> Data {
        let dim = max(1, size)
        let pixels = [UInt8](repeating: 0, count: dim * dim * 4)
        let data = Data(pixels)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let provider = CGDataProvider(data: data as CFData) else { return Data() }
        guard let image = CGImage(
            width: dim,
            height: dim,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dim * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return Data() }
        return UIImage(cgImage: image).pngData() ?? Data()
    }

    private func ensureConvolutionBuffers(dimOld: Int, dim: Int) {
        let intermediateSize = dimOld * dim
        if vDSPIntermediateSize != intermediateSize {
            vDSPIntermediateBuffer = Array(repeating: 0.0, count: intermediateSize)
            vDSPIntermediateSize = intermediateSize
        }

        let outputSize = dim * dim
        if vDSPOutputSize != outputSize {
            vDSPOutputBuffer = Array(repeating: 0.0, count: outputSize)
            vDSPOutputSize = outputSize
        }
    }

    private struct WorldPoint {
        let x: Double
        let y: Double
    }

    private struct WeightedPoint {
        let x: Double
        let y: Double
        let intensity: Double
    }

    private struct Bounds {
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double

        func intersects(_ other: Bounds) -> Bool {
            minX <= other.maxX &&
                maxX >= other.minX &&
                minY <= other.maxY &&
                maxY >= other.minY
        }
    }

    private struct ColorInterval {
        let color1: UInt32
        let color2: UInt32
        let duration: Double
    }

    private struct TileState {
        let points: [WeightedPoint]
        let bounds: Bounds?
        let radiusPx: Int
        let colorMap: [UInt32]
        let maxIntensities: [Double]
    }

    private let useAccelerateConvolution = true
    private let convolutionLock = NSLock()
    private var vDSPIntermediateBuffer: [Double] = []
    private var vDSPOutputBuffer: [Double] = []
    private var vDSPIntermediateSize = 0
    private var vDSPOutputSize = 0
    private lazy var emptyTileData: Data = HeatmapTileRenderer.makeEmptyTile(size: tileSize)

    public static let defaultTileSize = RasterSource.defaultTileSize
    public static let defaultCacheSizeKb = 8 * 1024
    private static let defaultRadiusPx = 20
    private static let defaultIntensity = 1.0
    private static let worldWidth = 1.0
    private static let screenSize = 1280.0
    private static let defaultMinZoom = 5
    private static let defaultMaxZoom = 11
    private static let maxZoomLevel = 22
    private static let colorMapSize = 1000
}
