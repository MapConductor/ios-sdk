import Foundation
import MapConductorCore
import UIKit

/**
 Renders a MapLibre vector style to raster tiles, for map backends that cannot
 display a vector style themselves.

 Register it with `TileServerRegistry.get()` and point a raster layer at the
 resulting route; the backend only ever sees ordinary raster tiles, which is
 what makes this work on MapKit, Google Maps, HERE, ArcGIS and the rest.

 Network I/O happens here rather than in the native library, so the app's own
 URLSession behaviour keeps applying: `headers` covers auth tokens, and
 `fetchTile` hands over completely.

 # Two layers, not one

 A style is served as **two** stacked raster layers rather than one. `groundTiles`
 draws fills, lines and circles — the half a GPU can draw, and the half no font
 arriving can change. `labelTiles` draws the labels and icons on a transparent
 ground. The map shows one map; the halves are rendered in parallel, and a glyph
 range landing redraws only the transparent half, so a label appearing never
 blanks the map beneath it.

 `renderTile(request:)` still draws both into one tile, for callers that want a
 single layer.
 */
public final class VectorTileProvider: TileProvider {
    public static let defaultTileSize = 512

    /**
     The least grain the label layer is drawn at, as a multiple of the tile size.

     Labels are the one thing on a map read as *shapes*, so they show a tile's
     resolution the way nothing else does. On a 1x screen this is what keeps
     them from looking like a fax; on a Retina screen `renderScale` already
     asks for those pixels and this adds nothing.
     */
    public static let labelResolution = 2

    /**
     How many pixels to draw per point of screen.

     Neither MapKit nor MapLibre asks for `@2x` tiles — both request at
     `pixelRatio` 1 — so a tile drawn at its nominal size is stretched across
     twice as many pixels on a Retina screen and every edge in it goes soft.
     Small text is where that shows first, because a label is read as a shape
     and a blurred shape reads as a smaller one.

     This changes sharpness only. **How large the map looks is set by the tile
     size the raster layer declares**, not by this: apparent size works out to
     the style's own value times `tileSize / 512`, so a style that reads small
     on a tablet wants a larger `tileSize`, not a larger scale.
     */
    private let renderScale: Int

    /// What a request should draw.
    public enum Content {
        /// Ground and labels in one tile: the single-layer behaviour.
        case full
        /// Fills, lines and circles. No labels, no icons, no glyph dependency.
        case ground
        /// Labels and icons on a transparent ground.
        case labels
    }

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

    // MARK: Style assets

    private let glyphCache: StyleAssetCache?
    private let spriteCache: StyleAssetCache?

    /// Rendered PNGs, so a second launch does not redraw what the first drew.
    private let diskCache: TileDiskCache?

    /// Identifies the style these tiles were drawn from. A restyle changes it,
    /// so the old tiles simply stop being found rather than needing to be
    /// hunted down and deleted.
    private var styleKey: String

    /// Glyph ranges somebody has already claimed, so two tiles wanting the
    /// same range do not both fetch it.
    private var requestedGlyphs = Set<String>()
    private let glyphsInFlight = Counter()

    /// Bumped when glyphs arrive, so tiles drawn before them stop being served.
    private let glyphGeneration = Counter()
    private var notifyPending = false

    /**
     Whether any tile has been drawn short of glyphs since the last handover.

     Most glyph arrivals change nothing: the ranges landed before anything
     needed them. Handing over anyway makes the map refetch and redraw the whole
     viewport to arrive at the same pixels.
     */
    private var provisionalSinceHandover = false

    /// True when the style names no `glyphs` template, so labels can never
    /// need one and none of the fetching below has anything to do.
    private let glyphsUnavailable: Bool

    /// Fetches source tiles several at a time.
    ///
    /// Sized for the whole viewport rather than one tile: a plan is nine
    /// fetches and a screen is several tiles, and fetching them one after
    /// another spends a second waiting for what takes a fraction of it at once.
    /// The threads spend their lives blocked on sockets, so they are cheap.
    private let fetchSlots = DispatchSemaphore(value: 16)
    private let fetchQueue = DispatchQueue(
        label: "mapconductor.vectortile.fetch", attributes: .concurrent
    )

    /// Narrower than the tile pool on purpose: glyph ranges compete with the
    /// source tiles that are needed to draw anything at all.
    private let glyphSlots = DispatchSemaphore(value: 6)

    /// One fetch per URL. Two tiles asking for the same source at the same
    /// moment would otherwise both pay for it.
    private var inFlight: [String: DispatchSemaphore] = [:]

    /// Told when glyphs arrive and tiles drawn before them are now stale.
    ///
    /// The host must make the map refetch: the tiles already on screen were
    /// drawn without those labels, and nothing else will replace them.
    public var onGlyphsLoaded: (() -> Void)?

    /// How long to let a burst of ranges settle before telling the host.
    ///
    /// A viewport's worth arrives within a second or two of each other, and
    /// notifying per range redraws every visible tile dozens of times to reach
    /// the same picture.
    private let notifyQuiet: DispatchTimeInterval = .milliseconds(400)

    /// How long to keep holding the window open while ranges are in flight.
    ///
    /// The quiet window alone is not enough: ranges do not arrive in one burst,
    /// so the window closes between them again and again and every close is a
    /// handover. The cap is there because a range that never answers must not
    /// hold the labels back forever.
    private let notifyMaxWait: TimeInterval = 10

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
        /// Where to keep glyph ranges, the sprite sheet, and rendered tiles
        /// between launches. Nil disables all three, at the cost of refetching
        /// and redrawing them on every cold start.
        assetCacheDirectory: URL? = nil,
        /// Budget for rendered tiles on disk. Rendered PNGs are 2-3x larger
        /// than a network tile would be — the encoder trades ratio for speed —
        /// so this is generous by design.
        renderedCacheBytes: Int = 48 * 1024 * 1024,
        /// Pixels drawn per point of screen. Defaults to the display's own
        /// scale, which is what stops a Retina screen stretching every tile.
        renderScale: Int? = nil,
        fetchTile: ((URL) -> Data?)? = nil
    ) throws {
        self.renderer = try VectorTileRenderer(styleJSON: styleJSON)
        self.tileSize = tileSize
        self.fetchTile = fetchTile ?? { url in VectorTileProvider.get(url, headers: headers) }
        cache.totalCostLimit = cacheBytes
        self.glyphsUnavailable = (try? renderer.glyphsURLTemplate()) == nil
        self.styleKey = Digest.hex(styleJSON)
        self.renderScale = max(1, renderScale ?? Int(UIScreen.main.scale.rounded()))

        // Separate directories: a glyph range and a sprite sheet have nothing
        // to do with each other, and clearing one should not take the other.
        self.glyphCache = assetCacheDirectory.flatMap {
            StyleAssetCache(directory: $0.appendingPathComponent("glyphs"))
        }
        self.spriteCache = assetCacheDirectory.flatMap {
            StyleAssetCache(directory: $0.appendingPathComponent("sprites"))
        }
        self.diskCache = assetCacheDirectory.flatMap {
            TileDiskCache(
                directory: $0.appendingPathComponent("tiles"),
                budgetBytes: renderedCacheBytes
            )
        }

        // Built at the size tiles are actually drawn at: the rasteriser has one
        // fixed target, so a scale it does not know about would be a readback
        // of the wrong size.
        let drawnSize = tileSize * self.renderScale
        switch renderMode {
        case .cpu:
            self.gpu = nil
        case .auto:
            self.gpu = MetalTileRasterizer.createOrNull(tileSize: drawnSize)
        case .gpu:
            // Explicitly asking for the GPU and quietly getting the CPU is the
            // failure that hides worst, so this one throws.
            guard let rasterizer = MetalTileRasterizer.createOrNull(tileSize: drawnSize) else {
                throw VectorTileError.renderFailed(MvtStatus.renderFailed)
            }
            self.gpu = rasterizer
        }

        warmStyleAssets()
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
        // Rendered tiles are written off the render thread; without this the
        // last few of a session never reach disk.
        diskCache?.flush()
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    // MARK: - What the host must show

    /**
     The credits this style's sources ask to be shown.

     These are not optional. A style is data under someone's licence, and a
     basemap drawing OpenStreetMap requires the credit; reading it out of the
     style and then not showing it is the one way this provider can be used
     wrongly without anything looking wrong. May contain HTML — the credit is
     normally a link to the licence.
     */
    public func attributions() -> [String] {
        (try? renderer.attributions()) ?? []
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
        // Rendered tiles are keyed by style, so the old ones simply stop being
        // found. Nothing has to be deleted.
        styleKey = Digest.hex(styleJSON)
        warmStyleAssets()
    }

    /// The generation to put in a tile URL, so tiles drawn short of their
    /// glyphs stop being served once the glyphs land.
    public var glyphGenerationValue: Int { glyphGeneration.value }

    // MARK: - The two halves

    /// The ground alone: fills, lines and circles, drawn on the GPU where there
    /// is one. Never invalidated by a font arriving.
    public private(set) lazy var groundTiles: TileProvider = Facade(self, .ground)

    /// The labels and icons alone, on a transparent ground.
    public private(set) lazy var labelTiles: TileProvider = Facade(self, .labels)

    /// One half of a split layer, as something a tile server can register.
    private final class Facade: TileProvider {
        private let content: Content
        private unowned let owner: VectorTileProvider

        init(_ owner: VectorTileProvider, _ content: Content) {
            self.owner = owner
            self.content = content
        }

        func renderTile(request: TileRequest) -> Data? {
            owner.renderTile(request: request, content: content) { false }
        }

        func renderTile(request: TileRequest, isCancelled: () -> Bool) -> Data? {
            owner.renderTile(request: request, content: content, isCancelled: isCancelled)
        }
    }

    public func renderTile(request: TileRequest) -> Data? {
        renderTile(request: request, content: .full) { false }
    }

    public func renderTile(request: TileRequest, isCancelled: () -> Bool) -> Data? {
        renderTile(request: request, content: .full, isCancelled: isCancelled)
    }

    /**
     Draws one tile.

     - Parameter isCancelled: asked repeatedly while the tile is being drawn.
       A map that has moved on is not owed this tile, and the render slots are
       shared, so a doomed tile is drawn *instead of* one still on screen.
     */
    public func renderTile(
        request: TileRequest,
        content: Content = .full,
        isCancelled: () -> Bool = { false }
    ) -> Data? {
        if isClosed || isCancelled() { return nil }

        let z = UInt8(clamping: request.z)
        let x = UInt32(clamping: request.x)
        let y = UInt32(clamping: request.y)

        /*
         Two keys, because a rendered tile goes stale for one reason only: it
         was drawn while some of its glyphs were still on the way. A tile that
         had them all is finished, and no later arrival can change it, so it is
         stored under a key with no generation in it and survives every
         handover. Only the ones drawn short are tied to the generation they
         were drawn at, and only they are redrawn.
         */
        func key(_ generation: String) -> String {
            Digest.hex(
                styleKey,
                "\(tileSize)",
                // A build that draws more than the one that filled this cache
                // must not serve its tiles.
                "v\(VectorTileRenderer.outputVersion)",
                generation,
                "\(request.z)/\(request.x)/\(request.y)"
            )
        }
        let completeKey: String? = diskCache.map { _ in
            switch content {
            // The ground has no glyphs to be short of; one key, forever.
            case .ground: return key("ground")
            case .labels: return key("labels-complete")
            case .full: return key("complete")
            }
        }
        let provisionalKey: String? = diskCache.flatMap { _ in
            switch content {
            case .ground: return nil
            case .labels: return key("labels-g\(glyphGeneration.value)")
            case .full: return key("g\(glyphGeneration.value)")
            }
        }
        for candidate in [completeKey, provisionalKey].compactMap({ $0 }) {
            if let hit = diskCache?.get(candidate) { return hit }
        }

        guard let plan = plan(z: z, x: x, y: y) else { return nil }

        // The ground never draws a label, so the ring of neighbours the label
        // pass asks for is nine fetches it has no use for. The entries stay in
        // place — the native side reads the plan positionally — but hold
        // nothing.
        let wanted = plan.map { entry in
            content == .ground && (entry["labelsOnly"] as? Bool ?? false)
                ? nil
                : (entry["url"] as? String).flatMap(VectorTileProvider.parse)
        }
        let tiles = fetchAll(wanted)
        if isClosed || isCancelled() { return nil }

        // Cached ranges belong in the store before the tile is judged to be
        // missing them; otherwise the first tile of a launch is drawn bare and
        // handed over a moment later for no reason. The ground has no glyphs,
        // so it never waits.
        let short = content != .ground && requestGlyphs(z: z, x: x, y: y, tiles: tiles)
        if short {
            lock.lock()
            provisionalSinceHandover = true
            lock.unlock()
        }
        if isCancelled() { return nil }

        let png: Data?
        switch content {
        case .labels:
            png = renderLabelTile(z: z, x: x, y: y, tiles: tiles)
        case .ground, .full:
            png = renderGroundTile(z: z, x: x, y: y, tiles: tiles, content: content)
        }

        if let png, let store = short ? provisionalKey : completeKey {
            diskCache?.put(store, png)
        }
        return png
    }

    private func plan(z: UInt8, x: UInt32, y: UInt32) -> [[String: Any]]? {
        guard let json = try? renderer.plan(z: z, x: x, y: y),
              let data = json.data(using: .utf8),
              let plan = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        return plan
    }

    /// The ground, on the GPU when there is one and the style paints nothing
    /// it cannot draw. `.full` composites labels over the readback.
    private func renderGroundTile(
        z: UInt8, x: UInt32, y: UInt32, tiles: [Data?], content: Content
    ) -> Data? {
        // A patterned fill needs an image repeated across a polygon, which the
        // GPU path cannot draw, so those tiles take the slower road.
        let onGpu = gpu != nil && !((try? renderer.needsCPU(z: z, tiles: tiles)) ?? false)
        if onGpu, let png = renderOnGpu(z: z, x: x, y: y, tiles: tiles, withLabels: content == .full) {
            gpuRenderCount.increment()
            return png
        }
        if onGpu { gpuFallbackCount.increment() }

        // A GPU failure must not lose the tile; the CPU can always draw it.
        let resolution = UInt32(tileSize * renderScale)
        if content == .ground {
            return try? renderer.renderGeometry(
                z: z, x: x, y: y, tileSize: resolution, tiles: tiles
            )
        }
        return try? renderer.render(z: z, x: x, y: y, tileSize: resolution, tiles: tiles)
    }

    /**
     The labels and icons on a transparent ground.

     Pure CPU: no GPU pass, no readback — which is the point of serving them as
     their own layer. Several of these run while the GPU draws the ground.
     */
    private func renderLabelTile(z: UInt8, x: UInt32, y: UInt32, tiles: [Data?]) -> Data? {
        // The larger of the two, not the product: `labelResolution` exists to
        // reach device resolution on a 1x screen, and `renderScale` already
        // does that on a Retina one. Multiplying them would draw sixteen times
        // the pixels for no visible gain.
        let resolution = tileSize * max(renderScale, VectorTileProvider.labelResolution)
        guard let drawn = try? renderer.renderLabels(
            z: z, x: x, y: y, tileSize: UInt32(resolution), tiles: tiles
        ) else { return nil }

        // A tile with nothing on it is common — water, fields — and one shared
        // transparent PNG serves them all.
        guard drawn.placed > 0, !drawn.pixels.isEmpty else { return emptyLabelTile }

        var pixels = drawn.pixels
        return pixels.withUnsafeMutableBytes { buffer -> Data? in
            guard let base = buffer.baseAddress else { return nil }
            // Premultiplied: the label pass writes colour already scaled by
            // alpha, and encoding that as straight alpha turns every halo grey.
            return TilePngEncoder.encode(
                rgba: base, width: resolution, height: resolution, premultiplied: true
            )
        }
    }

    /// One transparent tile, encoded once and served for every empty one.
    private lazy var emptyLabelTile: Data? = {
        var pixels = [UInt8](repeating: 0, count: 4)
        return pixels.withUnsafeMutableBytes { buffer -> Data? in
            guard let base = buffer.baseAddress else { return nil }
            return TilePngEncoder.encode(rgba: base, width: 1, height: 1, premultiplied: true)
        }
    }()

    private func renderOnGpu(
        z: UInt8, x: UInt32, y: UInt32, tiles: [Data?], withLabels: Bool
    ) -> Data? {
        guard let gpu else { return nil }
        do {
            let tessellated = try renderer.tessellate(
                z: z, x: x, y: y, tileSize: UInt32(tileSize * renderScale), tiles: tiles
            )
            // The tessellator draws fills and lines; labels come from a
            // distance field per glyph and are painted over the readback.
            // Without this the GPU path loses every label the style asked for.
            return gpu.renderPng(tessellated) { readback in
                guard withLabels else { return }
                _ = try? self.renderer.drawLabels(
                    z: z, x: x, y: y, tileSize: UInt32(self.tileSize * self.renderScale),
                    rgba: readback, tiles: tiles
                )
            }
        } catch {
            return nil
        }
    }

    // MARK: - Fetching

    /// Fetches a whole plan at once.
    ///
    /// A plan is nine tiles once the label pass asks for its neighbours, and
    /// nine round trips one after another is a second of waiting for what takes
    /// a fraction of it in parallel.
    private func fetchAll(_ urls: [URL?]) -> [Data?] {
        var results = [Data?](repeating: nil, count: urls.count)
        let group = DispatchGroup()
        let resultLock = NSLock()

        for (index, url) in urls.enumerated() {
            guard let url else { continue }
            fetchSlots.wait()
            group.enter()
            fetchQueue.async {
                defer {
                    self.fetchSlots.signal()
                    group.leave()
                }
                guard !self.isClosed else { return }
                let bytes = self.sourceTile(url)
                resultLock.lock()
                results[index] = bytes
                resultLock.unlock()
            }
        }
        group.wait()
        return results
    }

    private func sourceTile(_ url: URL) -> Data? {
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) { return cached as Data }

        lock.lock()
        if empties.contains(key) {
            lock.unlock()
            return nil
        }
        if let waiting = inFlight[key] {
            // Somebody else is already fetching this. Wait for them rather
            // than paying for the same bytes twice.
            lock.unlock()
            waiting.wait()
            waiting.signal()
            return cache.object(forKey: key as NSString) as Data?
        }
        let done = DispatchSemaphore(value: 0)
        inFlight[key] = done
        lock.unlock()

        defer {
            lock.lock()
            inFlight.removeValue(forKey: key)
            lock.unlock()
            done.signal()
        }

        guard let bytes = fetchTile(url), !bytes.isEmpty else {
            // Only a genuine "no tile" answer is remembered. A transient
            // failure blacklisted here would leave a hole for the session.
            lock.lock()
            empties.insert(key)
            lock.unlock()
            return nil
        }
        cache.setObject(bytes as NSData, forKey: key as NSString, cost: bytes.count)
        return bytes
    }

    // MARK: - Glyphs and sprites

    /// Loads whatever is already on disk, and fetches the sprite if it is not.
    private func warmStyleAssets() {
        guard !isClosed else { return }
        fetchQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            if let cache = self.glyphCache, let template = try? self.renderer.glyphsURLTemplate(),
               template != nil {
                // Nothing to enumerate a disk cache by — the ranges a style
                // wants are only known per tile — so warming happens as tiles
                // ask, through `requestGlyphs`, which checks the cache first.
                _ = cache
            }
            self.loadSprite()
        }
    }

    /// Fetches the sprite sheet, preferring what is already on disk.
    ///
    /// Icons are drawn only where the sheet has them, so until this lands a
    /// style's shields and pins are simply absent.
    private func loadSprite() {
        guard (try? renderer.needsSprite()) == true,
              let urls = try? renderer.spriteURLs(pixelRatio: 2)
        else { return }

        let index = spriteCache?.get(urls.json) ?? fetched(urls.json, into: spriteCache)
        let sheet = spriteCache?.get(urls.png) ?? fetched(urls.png, into: spriteCache)
        guard let index, let sheet,
              let text = String(data: index, encoding: .utf8), !isClosed
        else { return }
        _ = try? renderer.addSprite(json: text, png: sheet)
    }

    private func fetched(_ url: String, into store: StyleAssetCache?) -> Data? {
        guard let target = VectorTileProvider.parse(url),
              let bytes = fetchTile(target), !bytes.isEmpty
        else { return nil }
        store?.put(url, bytes)
        return bytes
    }

    /**
     Builds a URL from a string a style produced.

     `URL(string:)` returns nil for a space, and glyph URLs are full of them:
     the template's `{fontstack}` is a font *name*, so a MapLibre style asks for
     `.../font/Open Sans Semibold/0-255.pbf`. Rejecting those silently meant no
     glyph was ever fetched and no label was ever drawn, with nothing logged --
     the tiles came out bare and looked like a renderer that could not draw
     text.
     */
    static func parse(_ url: String) -> URL? {
        if let direct = URL(string: url) { return direct }
        return url
            .addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
            .flatMap(URL.init(string:))
    }

    /**
     Starts fetching the glyph ranges this tile's labels need, and returns.

     Waiting is the obvious thing and the wrong one: a range is a 0.4-1.3 second
     round trip, a tile at low zoom wants dozens, and waiting means the tile
     draws nothing until the last one lands. The tile is drawn with whatever is
     already in, exactly as MapLibre does it, and the ranges that arrive later
     bring their labels with them through `onGlyphsLoaded`.

     - Returns: whether this tile is about to be drawn without glyphs it wants,
       which is what decides whether a handover is worth making.
     */
    @discardableResult
    private func requestGlyphs(z: UInt8, x: UInt32, y: UInt32, tiles: [Data?]) -> Bool {
        if glyphsUnavailable || isClosed { return false }
        let needed = (try? renderer.neededGlyphs(z: z, x: x, y: y, tiles: tiles)) ?? []
        if needed.isEmpty { return false }

        lock.lock()
        let mine = needed.filter { requestedGlyphs.insert($0).inserted }
        lock.unlock()
        if mine.isEmpty { return true }

        for url in mine {
            glyphsInFlight.increment()
            glyphSlots.wait()
            fetchQueue.async { [weak self] in
                defer {
                    self?.glyphSlots.signal()
                    self?.glyphsInFlight.decrement()
                }
                guard let self, !self.isClosed else { return }
                // Ranges never change, so a hit here is kept without expiry.
                let bytes = self.glyphCache?.get(url) ?? self.fetched(url, into: self.glyphCache)
                guard let bytes, !bytes.isEmpty else { return }
                // Left in the claimed set on failure: a range the server does
                // not have will not appear on a retry.
                if let added = try? self.renderer.addGlyphs(bytes), added > 0 {
                    self.glyphsArrived()
                }
            }
        }
        return true
    }

    /**
     Tells the host that tiles drawn before now are missing labels.

     Coalesced: a viewport's worth of ranges lands in a burst, and asking the
     map to refetch on each one would redraw everything dozens of times for the
     same result. The generation is what makes the already-rendered tiles stale
     — without it the map's own cache keeps serving the unlabelled ones.
     */
    private func glyphsArrived() {
        glyphGeneration.increment()

        lock.lock()
        if notifyPending {
            lock.unlock()
            return
        }
        notifyPending = true
        lock.unlock()

        let deadline = Date().addingTimeInterval(notifyMaxWait)
        scheduleNotify(deadline: deadline)
    }

    private func scheduleNotify(deadline: Date) {
        fetchQueue.asyncAfter(deadline: .now() + notifyQuiet) { [weak self] in
            guard let self, !self.isClosed else { return }
            // Hold the window open while ranges are still coming, or the whole
            // viewport hands over once per range instead of once.
            if self.glyphsInFlight.value > 0, Date() < deadline {
                self.scheduleNotify(deadline: deadline)
                return
            }

            self.lock.lock()
            self.notifyPending = false
            // Nothing to hand over to: every tile drawn since the last one had
            // all the glyphs it wanted, so what is on screen is already the
            // finished picture.
            let worthIt = self.provisionalSinceHandover
            self.provisionalSinceHandover = false
            self.lock.unlock()

            if worthIt { self.onGlyphsLoaded?() }
        }
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

    func decrement() {
        lock.lock()
        count -= 1
        lock.unlock()
    }
}
