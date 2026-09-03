import Foundation
import MapConductorCore

/**
 Renders a MapLibre vector style to raster tiles, for map backends that cannot
 display a vector style themselves.

 Register it with `TileServerRegistry.get()` and point a raster layer at the
 resulting route; the backend only ever sees ordinary raster tiles, which is
 what makes this work on MapKit, Google Maps, HERE, ArcGIS and the rest.

 Network I/O happens here rather than in the native library, so the app's own
 URLSession behaviour keeps applying: `headers` covers auth tokens, and
 `fetchTile` hands over completely.
 */
public final class VectorTileProvider: TileProvider {
    public static let defaultTileSize = 512

    private let renderer: VectorTileRenderer
    private let tileSize: Int
    private let fetchTile: (URL) -> Data?

    /// Source tiles keyed by URL.
    ///
    /// Not an optimisation detail: neighbouring target tiles routinely need the
    /// same source tile — always, once overzoom kicks in, where one magnified
    /// ancestor serves 16 targets — and a map asks for a whole viewport at once.
    /// Budgeted in bytes via `totalCostLimit`, not in entries. Counting
    /// entries is the easy mistake: a basemap tile is 150-300 KB, so a few
    /// hundred of them is tens of megabytes.
    private let cache = NSCache<NSString, NSData>()
    /// Present only when GPU rendering is in use.
    private let gpu: MetalTileRasterizer?
    private let gpuRenderCount = Counter()
    private let gpuFallbackCount = Counter()
    /// URLs known to hold nothing, so a missing tile is not re-requested.
    private var empties = Set<String>()
    private let lock = NSLock()
    private var closed = false

    /// How tiles are turned into pixels.
    public enum RenderMode {
        /// tiny-skia on the CPU. Always available, and the only path that
        /// draws every layer type the renderer supports.
        case cpu
        /// Metal. Roughly twice as fast per tile, and — the reason it exists —
        /// it spends the map's time on a processor the rest of the app is not
        /// competing for.
        case gpu
        /// GPU where it initialises, CPU otherwise.
        case auto
    }

    /// Which path this provider actually took, after `auto` resolved.
    public var renderMode: RenderMode { gpu != nil ? .gpu : .cpu }

    /// Tiles drawn on the GPU, and tiles that asked for the GPU and fell back.
    ///
    /// Worth reading in tests: a silent fallback looks exactly like success
    /// from the outside, and a suite once passed with the GPU path failing on
    /// every single tile.
    public var gpuRenders: Int { gpuRenderCount.value }
    public var gpuFallbacks: Int { gpuFallbackCount.value }

    /// - Throws: `VectorTileError.styleRejected` if the style cannot be parsed,
    ///   or `renderFailed` if `renderMode` is `.gpu` and Metal is unavailable.
    public init(
        styleJSON: String,
        tileSize: Int = VectorTileProvider.defaultTileSize,
        headers: [String: String] = [:],
        cacheBytes: Int = 16 * 1024 * 1024,
        renderMode: RenderMode = .auto,
        fetchTile: ((URL) -> Data?)? = nil
    ) throws {
        self.renderer = try VectorTileRenderer(styleJSON: styleJSON)
        self.tileSize = tileSize
        self.fetchTile = fetchTile ?? { url in VectorTileProvider.get(url, headers: headers) }
        cache.totalCostLimit = cacheBytes

        switch renderMode {
        case .cpu:
            self.gpu = nil
        case .auto:
            self.gpu = MetalTileRasterizer.createOrNull(tileSize: tileSize)
        case .gpu:
            // Explicitly asking for the GPU and quietly getting the CPU is the
            // failure that hides worst, so this one throws.
            guard let rasterizer = MetalTileRasterizer.createOrNull(tileSize: tileSize) else {
                throw VectorTileError.renderFailed(MvtStatus.renderFailed)
            }
            self.gpu = rasterizer
        }
    }

    deinit {
        close()
    }

    /// Releases the native renderer. Safe to call more than once.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        cache.removeAllObjects()
        empties.removeAll()
        renderer.close()
    }

    /// Reasons the current style may not render as intended.
    public func diagnostics() -> [String] {
        (try? renderer.diagnostics()) ?? []
    }

    /// Replaces the style. Fetched vector tiles stay valid — the geometry is
    /// unchanged, only the paint applied to it — so recolouring costs a
    /// re-rasterise and no network traffic.
    ///
    /// The caller still has to make the map drop its *raster* tiles; pass a new
    /// `cacheKey` to `LocalTileServer.urlTemplate`.
    public func setStyle(_ styleJSON: String) throws {
        try renderer.setStyle(styleJSON)
    }

    public func renderTile(request: TileRequest) -> Data? {
        lock.lock()
        let isClosed = closed
        lock.unlock()
        if isClosed { return nil }

        let z = UInt8(clamping: request.z)
        let x = UInt32(clamping: request.x)
        let y = UInt32(clamping: request.y)

        guard let planJSON = try? renderer.plan(z: z, x: x, y: y),
              let planData = planJSON.data(using: .utf8),
              let plan = try? JSONSerialization.jsonObject(with: planData) as? [[String: Any]]
        else { return nil }

        let tiles: [Data?] = plan.map { entry in
            guard let raw = entry["url"] as? String, let url = URL(string: raw) else { return nil }
            return sourceTile(url)
        }

        if gpu != nil, let png = renderOnGpu(z: z, x: x, y: y, tiles: tiles) {
            gpuRenderCount.increment()
            return png
        }
        if gpu != nil { gpuFallbackCount.increment() }

        return try? renderer.render(z: z, x: x, y: y, tileSize: UInt32(tileSize), tiles: tiles)
    }

    private func renderOnGpu(z: UInt8, x: UInt32, y: UInt32, tiles: [Data?]) -> Data? {
        guard let gpu else { return nil }
        do {
            let tessellated = try renderer.tessellate(
                z: z, x: x, y: y, tileSize: UInt32(tileSize), tiles: tiles
            )
            return gpu.renderPng(tessellated)
        } catch {
            return nil
        }
    }

    private func sourceTile(_ url: URL) -> Data? {
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) { return cached as Data }

        lock.lock()
        let known = empties.contains(key)
        lock.unlock()
        if known { return nil }

        guard let bytes = fetchTile(url), !bytes.isEmpty else {
            lock.lock()
            empties.insert(key)
            lock.unlock()
            return nil
        }
        cache.setObject(bytes as NSData, forKey: key as NSString, cost: bytes.count)
        return bytes
    }

    /// Synchronous by design: `renderTile` is already called off the main
    /// thread by the tile server, and the plan/render contract is positional.
    private static func get(_ url: URL, headers: [String: String]) -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        var payload: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            // A missing tile is normal at the edge of a source's coverage.
            guard (200..<300).contains(http.statusCode) else { return }
            payload = data
        }.resume()
        done.wait()
        return payload
    }
}

/// A counter that is safe to read from whichever thread the tile server used.
private final class Counter {
    private var count = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
