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
}
