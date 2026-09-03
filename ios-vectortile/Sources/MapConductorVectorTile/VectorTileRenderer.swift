import CMvtRender
import Foundation

public enum VectorTileError: Error, CustomStringConvertible {
    case styleRejected(String)
    case renderFailed(Int32)
    case closed

    public var description: String {
        switch self {
        case .styleRejected(let message): return "style rejected: \(message)"
        case .renderFailed(let code): return "render failed with code \(code)"
        case .closed: return "renderer has been closed"
        }
    }
}

/// Renders MapLibre vector styles to raster PNG tiles.
///
/// Rendering is split in two so that **no network I/O happens inside the native
/// library**: ``plan(z:x:y:)`` says which source tiles are needed, the caller
/// fetches them with URLSession — keeping its own auth headers, pinning and
/// cache — and passes the bytes to ``render(z:x:y:tileSize:tiles:)``.
public final class VectorTileRenderer {
    public static let defaultTileSize: UInt32 = 512

    private var handle: OpaquePointer?

    /// - Throws: ``VectorTileError/styleRejected(_:)`` if the style cannot be parsed.
    public init(styleJSON: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let created = styleJSON.withCString { mvt_renderer_new($0, &errorPointer) }
        guard let created else {
            let message = errorPointer.map { pointer -> String in
                defer { mvt_string_free(pointer) }
                return String(cString: pointer)
            } ?? "unknown error"
            throw VectorTileError.styleRejected(message)
        }
        // `MvtRenderer` is an incomplete C struct, so Swift models it as an
        // OpaquePointer rather than a typed pointer.
        handle = created
    }

    deinit {
        close()
    }

    /// Releases the native renderer. Safe to call more than once.
    public func close() {
        guard let live = handle else { return }
        // Clearing first keeps a double close from freeing the same pointer twice.
        handle = nil
        mvt_renderer_free(live)
    }

    private func requireHandle() throws -> OpaquePointer {
        guard let live = handle else { throw VectorTileError.closed }
        return live
    }

    /// Source tiles needed to draw `z/x/y`, as JSON. Fetch them in order and
    /// pass the bytes to ``render(z:x:y:tileSize:tiles:)`` positionally.
    public func plan(z: UInt8, x: UInt32, y: UInt32) throws -> String {
        let live = try requireHandle()
        guard let json = mvt_renderer_plan(live, z, x, y) else { return "[]" }
        defer { mvt_string_free(json) }
        return String(cString: json)
    }

    /// Replaces the style. Fetched vector tiles stay valid — the geometry is
    /// unchanged, only the paint applied to it — so recolouring needs no refetch.
    public func setStyle(_ styleJSON: String) throws {
        let live = try requireHandle()
        var errorPointer: UnsafeMutablePointer<CChar>?
        let code = styleJSON.withCString { mvt_renderer_set_style(live, $0, &errorPointer) }
        guard code == MVT_OK else {
            let message = errorPointer.map { pointer -> String in
                defer { mvt_string_free(pointer) }
                return String(cString: pointer)
            } ?? "unknown error"
            throw VectorTileError.styleRejected(message)
        }
    }

    /// Layer `type` values in the current style that will not be drawn.
    public func unsupportedLayerTypes() throws -> [String] {
        let live = try requireHandle()
        guard let json = mvt_renderer_unsupported_layer_types(live) else { return [] }
        defer { mvt_string_free(json) }
        let text = String(cString: json)
        return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    /// Reasons the current style may not render as intended: unsupported layer
    /// types, sources that cannot be fetched, layers pointing at undefined
    /// sources, Mapbox `imports`.
    ///
    /// Worth surfacing — the failure mode that matters is a blank tile, and a
    /// style this renderer cannot use should say so.
    public func diagnostics() throws -> [String] {
        let live = try requireHandle()
        guard let json = mvt_renderer_diagnostics(live) else { return [] }
        defer { mvt_string_free(json) }
        let text = String(cString: json)
        return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    /// Rasterises `z/x/y` to PNG bytes.
    ///
    /// - Parameter tiles: one entry per ``plan(z:x:y:)`` request, in the same
    ///   order; `nil` where the fetch produced nothing.
    public func render(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        tiles: [Data?]
    ) throws -> Data {
        let live = try requireHandle()

        // The native side takes one concatenated buffer plus a length table,
        // which avoids marshalling an array-of-arrays across the ABI.
        var lengths = [UInt32]()
        var payload = Data()
        lengths.reserveCapacity(tiles.count)
        for tile in tiles {
            lengths.append(UInt32(tile?.count ?? 0))
            if let tile { payload.append(tile) }
        }

        var outPointer: UnsafeMutablePointer<UInt8>?
        var outLength = 0

        let code: Int32 = payload.withUnsafeBytes { payloadBuffer in
            lengths.withUnsafeBufferPointer { lengthBuffer in
                mvt_renderer_render(
                    live,
                    z, x, y, tileSize,
                    payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                    payload.count,
                    lengthBuffer.baseAddress,
                    lengthBuffer.count,
                    &outPointer,
                    &outLength
                )
            }
        }

        guard code == MVT_OK, let outPointer else {
            throw VectorTileError.renderFailed(code)
        }
        defer { mvt_buffer_free(outPointer, outLength) }
        return Data(bytes: outPointer, count: outLength)
    }
    /// Tessellates `z/x/y` into triangles for GPU drawing.
    ///
    /// - Parameter tiles: as in ``render(z:x:y:tileSize:tiles:)``.
    public func tessellate(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        tiles: [Data?]
    ) throws -> TessellatedTile {
        let live = try requireHandle()

        var lengths = [UInt32]()
        var payload = Data()
        lengths.reserveCapacity(tiles.count)
        for tile in tiles {
            lengths.append(UInt32(tile?.count ?? 0))
            if let tile { payload.append(tile) }
        }

        var outPointer: UnsafeMutablePointer<Float>?
        var outLength = 0

        let code: Int32 = payload.withUnsafeBytes { payloadBuffer in
            lengths.withUnsafeBufferPointer { lengthBuffer in
                mvt_renderer_tessellate(
                    live,
                    z, x, y, tileSize,
                    payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                    payload.count,
                    lengthBuffer.baseAddress,
                    lengthBuffer.count,
                    &outPointer,
                    &outLength
                )
            }
        }

        guard code == MVT_OK, let outPointer else {
            throw VectorTileError.renderFailed(code)
        }
        defer { mvt_floats_free(outPointer, outLength) }
        return TessellatedTile(
            packed: Array(UnsafeBufferPointer(start: outPointer, count: outLength))
        )
    }

    /// Encodes straight-alpha RGBA pixels as PNG.
    ///
    /// Worth crossing the ABI for: the native encoder measures about 7 ms per
    /// tile where the platform one takes nearer 48 ms, which is the difference
    /// between the GPU path being worth having and not.
    public static func encodePng(rgba: UnsafeRawBufferPointer, width: UInt32, height: UInt32) throws -> Data {
        var outPointer: UnsafeMutablePointer<UInt8>?
        var outLength = 0
        let code = mvt_encode_png(
            rgba.bindMemory(to: UInt8.self).baseAddress,
            width, height,
            &outPointer, &outLength
        )
        guard code == MVT_OK, let outPointer else {
            throw VectorTileError.renderFailed(code)
        }
        defer { mvt_buffer_free(outPointer, outLength) }
        return Data(bytes: outPointer, count: outLength)
    }

}

/// A tile reduced to triangles, as the native side packs it.
///
/// One flat `[Float]` rather than a decoded object graph: it crosses the C ABI
/// as a single allocation, and the parts the GPU consumes — vertices, batch
/// ranges — are read straight out of it without copying.
public struct TessellatedTile {
    /// Where the fixed-size prologue ends and the batch table begins.
    private static let headerFloats = 13

    public let packed: [Float]

    public init(packed: [Float]) {
        self.packed = packed
    }

    /// Tile-unit coordinate space the vertices live in.
    public var extent: Float { packed.isEmpty ? 0 : packed[0] }

    /// The style's background colour, if it declares one.
    public var background: (r: Float, g: Float, b: Float, a: Float)? {
        guard packed.count >= 6, packed[1] != 0 else { return nil }
        return (packed[2], packed[3], packed[4], packed[5])
    }

    public var batchCount: Int { packed.count > 6 ? Int(packed[6]) : 0 }

    /// Native timings in milliseconds: decode, tessellate, filter compile,
    /// fill, line.
    public var timings: (decode: Float, tessellate: Float, filterCompile: Float, fill: Float, line: Float) {
        guard packed.count >= Self.headerFloats else { return (0, 0, 0, 0, 0) }
        return (packed[7], packed[8], packed[9], packed[10], packed[11])
    }

    /// Vertex range of one draw call. Batches stay separate to preserve
    /// painter's order.
    public func batch(_ index: Int) -> (firstVertex: Int, vertexCount: Int) {
        let base = Self.headerFloats + index * 2
        return (Int(packed[base]), Int(packed[base + 1]))
    }

    /// Offset into `packed` where the interleaved vertices start.
    public var vertexOffset: Int { Self.headerFloats + batchCount * 2 }

    /// Floats per vertex: x, y, r, g, b, a.
    public static let vertexStride = 6

    public var vertexFloatCount: Int { max(0, packed.count - vertexOffset) }

    /// Runs `body` with the vertex data only, without copying it out.
    public func withVertices<R>(_ body: (UnsafeBufferPointer<Float>) -> R) -> R {
        packed.withUnsafeBufferPointer { buffer in
            body(UnsafeBufferPointer(rebasing: buffer[vertexOffset...]))
        }
    }
}

/// Status codes from the native ABI.
///
/// Restated here because Swift's C importer only brings across `MVT_OK`; the
/// error macros start with a minus and are dropped. Mirrors `mvt_render.h`.
public enum MvtStatus {
    public static let ok: Int32 = 0
    public static let nullHandle: Int32 = -1
    public static let badArgument: Int32 = -2
    public static let renderFailed: Int32 = -3
    public static let panic: Int32 = -4
}
