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

/// Presents `tiles` the way every native entry point takes them: one
/// concatenated buffer plus a length table, `0` marking a tile that failed to
/// fetch.
///
/// An array-of-arrays would need a marshaller on every platform; this needs
/// none, which is why the JNI, C and wasm surfaces all agree on it.
private func withTiles<R>(
    _ tiles: [Data?],
    _ body: (UnsafePointer<UInt8>?, Int, UnsafePointer<UInt32>?, Int) -> R
) -> R {
    var lengths = [UInt32]()
    var payload = Data()
    lengths.reserveCapacity(tiles.count)
    for tile in tiles {
        lengths.append(UInt32(tile?.count ?? 0))
        if let tile { payload.append(tile) }
    }
    return payload.withUnsafeBytes { payloadBuffer in
        lengths.withUnsafeBufferPointer { lengthBuffer in
            body(
                payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                payload.count,
                lengthBuffer.baseAddress,
                lengthBuffer.count
            )
        }
    }
}

private func takeStrings(_ json: UnsafeMutablePointer<CChar>?) -> [String] {
    guard let json else { return [] }
    defer { mvt_string_free(json) }
    let text = String(cString: json)
    return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
}

/// Labels and icons drawn on a transparent ground.
public struct LabelTile {
    /// **Premultiplied** RGBA, `tileSize * tileSize * 4` bytes. Empty when
    /// nothing was placed.
    ///
    /// Premultiplied, not straight: encoding these as straight alpha turns
    /// every halo grey.
    public let pixels: Data

    /// How many labels were placed. Zero means the tile is empty, and the
    /// caller should serve one shared transparent image rather than encode it.
    public let placed: Int
}

/// Renders MapLibre vector styles to raster PNG tiles.
///
/// Rendering is split in two so that **no network I/O happens inside the native
/// library**: ``plan(z:x:y:)`` says which source tiles are needed, the caller
/// fetches them with URLSession — keeping its own auth headers, pinning and
/// cache — and passes the bytes to ``render(z:x:y:tileSize:tiles:)``.
public final class VectorTileRenderer {
    public static let defaultTileSize: UInt32 = 512

    /**
     What this renderer draws, as a number that goes up whenever it draws more.

     Rendered tiles are cached on disk across launches, and a cache keyed only
     by style and coordinates is keyed by *what the style says*, not by *what
     the renderer did with it*. The build that started drawing labels kept
     serving the unlabelled PNGs the previous one had cached — correct for the
     renderer that made them, wrong for the one asking.

     Kept in step with the Android binding's `OUTPUT_VERSION`: they cache the
     output of the same native renderer.

     18: glyph pixels align across tile boundaries.
     19: label bounds include glyph bearings and SDF raster extents.
     20: that extent decides which tile a label draws in; collisions are
         judged on the layout box again, so labels are as dense as before.
     */
    public static let outputVersion = 23

    private var handle: OpaquePointer?

    /**
     - Parameter displayTileSize: how many points of screen one tile covers
       where the host shows it. **Not** the pixel count a render is asked for:
       the label pass draws at twice the pixels, and a 256pt tile is still
       256pt however many pixels it carries. It fixes the size the style draws
       at and the zoom its expressions are read at, so passing the wrong one
       draws every label and every road at the wrong size. 512 is what a
       raster source declared at 512 gets.
     - Throws: ``VectorTileError/styleRejected(_:)`` if the style cannot be parsed.
     */
    public init(styleJSON: String, displayTileSize: Int = 512) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let created = styleJSON.withCString {
            mvt_renderer_new($0, UInt32(max(1, displayTileSize)), &errorPointer)
        }
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
        pthread_rwlock_init(&liveCalls, nil)
    }

    /**
     Holds the renderer alive for the length of a native call.

     `close()` frees the native renderer, and a call already inside it on
     another thread then reads freed memory. That is not hypothetical: the
     provider is rebuilt when the map under it changes its tile size, and
     ArcGIS's tiles are drawn on a queue of their own, so a render was still
     running when the old provider closed — and the app went to the home
     screen a second after switching to ArcGIS. android-sdk's binding hit the
     same fault (SIGSEGV in `nativeRender`, fault address made of style bytes)
     and holds the same lock.

     Calls take the read side, close takes the write side and so waits for
     every call in flight. A call that arrives after the close finds the
     handle cleared and throws instead of touching freed memory.
     */
    private var liveCalls = pthread_rwlock_t()

    deinit {
        close()
        pthread_rwlock_destroy(&liveCalls)
    }

    /// Releases the native renderer. Safe to call more than once. Waits for
    /// any call in flight; never frees under one.
    public func close() {
        pthread_rwlock_wrlock(&liveCalls)
        defer { pthread_rwlock_unlock(&liveCalls) }
        guard let live = handle else { return }
        // Clearing first keeps a double close from freeing the same pointer twice.
        handle = nil
        mvt_renderer_free(live)
    }

    /// Runs one native call with the renderer held alive for its duration.
    private func withRenderer<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        pthread_rwlock_rdlock(&liveCalls)
        defer { pthread_rwlock_unlock(&liveCalls) }
        guard let live = handle else { throw VectorTileError.closed }
        return try body(live)
    }

    /// Source tiles needed to draw `z/x/y`, as JSON. Fetch them in order and
    /// pass the bytes to ``render(z:x:y:tileSize:tiles:)`` positionally.
    public func plan(z: UInt8, x: UInt32, y: UInt32) throws -> String {
        return try withRenderer { live in
            guard let json = mvt_renderer_plan(live, z, x, y) else { return "[]" }
            defer { mvt_string_free(json) }
            return String(cString: json)
        }
    }

    /// Replaces the style. Fetched vector tiles stay valid — the geometry is
    /// unchanged, only the paint applied to it — so recolouring needs no refetch.
    public func setStyle(_ styleJSON: String) throws {
        return try withRenderer { live in
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
    }

    /// Layer `type` values in the current style that will not be drawn.
    public func unsupportedLayerTypes() throws -> [String] {
        return try withRenderer { live in
            guard let json = mvt_renderer_unsupported_layer_types(live) else { return [] }
            defer { mvt_string_free(json) }
            let text = String(cString: json)
            return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
        }
    }

    /// Reasons the current style may not render as intended: unsupported layer
    /// types, sources that cannot be fetched, layers pointing at undefined
    /// sources, Mapbox `imports`.
    ///
    /// Worth surfacing — the failure mode that matters is a blank tile, and a
    /// style this renderer cannot use should say so.
    public func diagnostics() throws -> [String] {
        return try withRenderer { live in
            guard let json = mvt_renderer_diagnostics(live) else { return [] }
            defer { mvt_string_free(json) }
            let text = String(cString: json)
            return (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
        }
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
        return try withRenderer { live in

            // The native side takes one concatenated buffer plus a length table,
            // which avoids marshalling an array-of-arrays across the ABI.
            var outPointer: UnsafeMutablePointer<UInt8>?
            var outLength = 0

            let code = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_render(
                    live, z, x, y, tileSize,
                    data, dataLength, lengths, lengthsCount,
                    &outPointer, &outLength
                )
            }

            guard code == MVT_OK, let outPointer else {
                throw VectorTileError.renderFailed(code)
            }
            defer { mvt_buffer_free(outPointer, outLength) }
            return Data(bytes: outPointer, count: outLength)
        }
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
        return try withRenderer { live in

            var outPointer: UnsafeMutablePointer<Float>?
            var outLength = 0

            let code = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_tessellate(
                    live, z, x, y, tileSize,
                    data, dataLength, lengths, lengthsCount,
                    &outPointer, &outLength
                )
            }

            guard code == MVT_OK, let outPointer else {
                throw VectorTileError.renderFailed(code)
            }
            defer { mvt_floats_free(outPointer, outLength) }
            return TessellatedTile(
                packed: Array(UnsafeBufferPointer(start: outPointer, count: outLength))
            )
        }
    }

    // MARK: - Labels and icons

    /// The credits this style's sources ask to be shown.
    ///
    /// The host must display these: a style is data under someone's licence,
    /// and a basemap drawing OpenStreetMap requires the credit. May contain
    /// HTML — the text is normally a link to the licence.
    public func attributions() throws -> [String] {
        takeStrings(try withRenderer { mvt_renderer_attributions($0) })
    }

    /// The style's `glyphs` URL template, or nil when it names none.
    public func glyphsURLTemplate() throws -> String? {
        return try withRenderer { live in
            guard let json = mvt_renderer_glyphs_url_template(live) else { return nil }
            defer { mvt_string_free(json) }
            return String(cString: json)
        }
    }

    /// URLs of the glyph ranges this tile's labels need and the store has not
    /// got. Fetch them, then feed each back through ``addGlyphs(_:)``.
    ///
    /// Empty when the style names no template, or everything needed is loaded.
    public func neededGlyphs(z: UInt8, x: UInt32, y: UInt32, tiles: [Data?]) throws -> [String] {
        return try withRenderer { live in
            let json = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_needed_glyphs(live, z, x, y, data, dataLength, lengths, lengthsCount)
            }
            return takeStrings(json)
        }
    }

    /// Adds one fetched glyph range. Returns how many glyphs it carried.
    ///
    /// Labels are drawn with whatever is loaded when the tile is drawn, so a
    /// range arriving later means redrawing the tiles that wanted it.
    @discardableResult
    public func addGlyphs(_ pbf: Data) throws -> Int {
        return try withRenderer { live in
            let count = pbf.withUnsafeBytes { buffer in
                mvt_renderer_add_glyphs(
                    live, buffer.bindMemory(to: UInt8.self).baseAddress, pbf.count
                )
            }
            guard count >= 0 else { throw VectorTileError.renderFailed(count) }
            return Int(count)
        }
    }

    /// Whether any glyph has been loaded. Labels need at least one.
    public func hasGlyphs() throws -> Bool {
        try withRenderer { mvt_renderer_has_glyphs($0) == 1 }
    }

    /// The sprite sheet's `.json` and `.png` URLs, or nil when the style names
    /// no sprite. Fetch both and pass them to ``addSprite(json:png:)``.
    public func spriteURLs(pixelRatio: UInt32 = 2) throws -> (json: String, png: String)? {
        let urls = takeStrings(try withRenderer { mvt_renderer_sprite_urls($0, pixelRatio) })
        guard urls.count == 2 else { return nil }
        return (json: urls[0], png: urls[1])
    }

    /// Adds the fetched sprite sheet. Returns how many icons it carried.
    @discardableResult
    public func addSprite(json: String, png: Data) throws -> Int {
        return try withRenderer { live in
            let count = json.withCString { index in
                png.withUnsafeBytes { buffer in
                    mvt_renderer_add_sprite(
                        live, index, buffer.bindMemory(to: UInt8.self).baseAddress, png.count
                    )
                }
            }
            guard count >= 0 else { throw VectorTileError.renderFailed(count) }
            return Int(count)
        }
    }

    /// Whether the style names a sprite the renderer has not been given yet.
    public func needsSprite() throws -> Bool {
        try withRenderer { mvt_renderer_needs_sprite($0) == 1 }
    }

    /// Whether this tile must be drawn on the CPU because the style paints
    /// a pattern the GPU cannot draw or a polygon that is too costly to triangulate.
    public func needsCPU(z: UInt8, tiles: [Data?]) throws -> Bool {
        return try withRenderer { live in
            return withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_needs_cpu(live, z, data, dataLength, lengths, lengthsCount)
            } == 1
        }
    }

    /// Rasterises the ground alone — fills, lines and circles, no labels or
    /// icons — to PNG bytes.
    ///
    /// The half of a split layer that a GPU draws and that fonts arriving never
    /// invalidate. Serve this and ``renderLabels(z:x:y:tileSize:tiles:)`` as two
    /// stacked raster layers and the map shows one; the halves are drawn in
    /// parallel, and a font landing redraws only the transparent one.
    public func renderGeometry(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        tiles: [Data?]
    ) throws -> Data {
        return try withRenderer { live in
            var outPointer: UnsafeMutablePointer<UInt8>?
            var outLength = 0

            let code = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_render_geometry(
                    live, z, x, y, tileSize,
                    data, dataLength, lengths, lengthsCount,
                    &outPointer, &outLength
                )
            }
            guard code == MVT_OK, let outPointer else {
                throw VectorTileError.renderFailed(code)
            }
            defer { mvt_buffer_free(outPointer, outLength) }
            return Data(bytes: outPointer, count: outLength)
        }
    }

    /// Draws the labels and icons alone, on a transparent ground.
    ///
    /// The other half of a split layer. A ``LabelTile`` whose `placed` is zero
    /// carries no pixels — water and fields are common, and one shared
    /// transparent image serves them all.
    public func renderLabels(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        tiles: [Data?]
    ) throws -> LabelTile {
        return try withRenderer { live in
            var outPointer: UnsafeMutablePointer<UInt8>?
            var outLength = 0
            var placed = 0

            let code = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_render_labels(
                    live, z, x, y, tileSize,
                    data, dataLength, lengths, lengthsCount,
                    &outPointer, &outLength, &placed
                )
            }
            guard code == MVT_OK else { throw VectorTileError.renderFailed(code) }
            guard let outPointer else { return LabelTile(pixels: Data(), placed: placed) }
            defer { mvt_buffer_free(outPointer, outLength) }
            return LabelTile(pixels: Data(bytes: outPointer, count: outLength), placed: placed)
        }
    }

    /// Draws labels and icons over pixels the caller already has — a GPU
    /// readback, typically — in place. Returns how many labels were placed.
    ///
    /// `rgba` must hold exactly `tileSize * tileSize * 4` bytes and is read as
    /// **straight** alpha, which is what a Metal readback is.
    @discardableResult
    public func drawLabels(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        rgba: inout Data,
        tiles: [Data?]
    ) throws -> Int {
        try rgba.withUnsafeMutableBytes { pixels in
            try drawLabels(z: z, x: x, y: y, tileSize: tileSize, rgba: pixels, tiles: tiles)
        }
    }

    /// The same, painting straight into a buffer the caller already holds — a
    /// GPU readback, which is the whole reason this overload exists. Copying a
    /// tile in and out to add labels costs more than drawing them.
    @discardableResult
    public func drawLabels(
        z: UInt8,
        x: UInt32,
        y: UInt32,
        tileSize: UInt32 = defaultTileSize,
        rgba: UnsafeMutableRawBufferPointer,
        tiles: [Data?]
    ) throws -> Int {
        return try withRenderer { live in
            let placed = withTiles(tiles) { data, dataLength, lengths, lengthsCount in
                mvt_renderer_draw_labels(
                    live, z, x, y, tileSize,
                    rgba.bindMemory(to: UInt8.self).baseAddress, rgba.count,
                    data, dataLength, lengths, lengthsCount
                )
            }
            guard placed >= 0 else { throw VectorTileError.renderFailed(placed) }
            return Int(placed)
        }
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
