import Foundation
import MapConductorCore
import MapConductorVectorTile

/**
 Holds the vector tile provider and the two raster layers it feeds.

 The style is served as **two** stacked raster layers rather than one. The
 ground draws fills, lines and circles — the half no font arriving can change.
 The overlay draws labels and icons on a transparent ground. To the map and the
 user they read as one layer; the halves render in parallel, and a glyph range
 landing redraws only the transparent one.
 */
@MainActor
final class VectorTilePageViewModel: ObservableObject {
    /// Central Tokyo: the OSMF service has street-level detail here, so the
    /// layer is obviously doing something at the default zoom.
    let initCameraPosition = MapCameraPosition(
        position: GeoPoint(latitude: 35.68049, longitude: 139.76669),
        zoom: 12.0
    )

    @Published private(set) var ground: RasterLayerState?
    @Published private(set) var labels: RasterLayerState?
    @Published private(set) var failure: String?
    @Published private(set) var diagnostics: [String] = []

    /// Credits the style's sources ask to be shown. Not optional: this page
    /// draws OpenStreetMap, whose licence requires them.
    @Published private(set) var attributions: [String] = []

    /// What the label overlay is keyed by. Bumped when glyphs arrive, so the
    /// map drops the tiles that were drawn without them.
    @Published private(set) var generation = 0

    /**
     The zoom the backend actually asked for, and at what pixel ratio.

     Not a detail: a backend whose tile grid is 256 points per tile asks for one
     zoom deeper than a 512-CSS-px grid does for the same camera, and a tile
     rendered for the wrong grid comes out at the wrong size — text most
     visibly, because thin roads just look like thin roads. Reading it back on
     the device is the only way to know which grid a given SDK is using.
     */
    @Published private(set) var observed = "-"

    private let probe = TileGridProbe()

    private let routeId = "sample-vectortile-\(UUID().uuidString)"
    private var provider: VectorTileProvider?

    /**
     How many points of screen one tile covers.

     Not a lever for how large the text is. Apparent size works out to the
     style's own value times `tileSize / 512`, but the number of tiles across
     the screen scales the same way, so doubling this is exactly a one-step
     zoom: the map gets bigger and the text keeps its size *relative to the
     map*. Tried on an iPad at 1024 — the labels came out twice the size and so
     did every road, which is a zoomed-in map, not a more readable one.

     Text that is too small relative to the map is the style's `text-size`, and
     nothing here can fix it.

     Only 512 and 1024 are available in any case: MapKit's tile grid is built
     from 256, and a size that is not a power-of-two multiple of it draws a
     blank map. 768 was tried and drew nothing at all.
     */
    private let tileSize = 512

    private var groundRoute: String { "\(routeId)-ground" }
    private var labelRoute: String { "\(routeId)-labels" }

    func load() async {
        guard provider == nil, failure == nil else { return }
        do {
            let styleText = try await VectorTileStyleLoader.load()
            let cacheDirectory = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("vectortile")

            let created = try VectorTileProvider(
                styleJSON: styleText,
                tileSize: tileSize,
                assetCacheDirectory: cacheDirectory
            )
            // Glyphs arrive after the tiles that need them: a range is a round
            // trip and a tile at low zoom wants dozens, so tiles are drawn with
            // whatever is loaded and the overlay is replaced once more arrives.
            created.onGlyphsLoaded = { [weak self] in
                Task { @MainActor in self?.handOverLabels() }
            }
            provider = created

            let server = TileServerRegistry.get()
            probe.onObserve = { [weak self] text in
                Task { @MainActor in self?.observed = text }
            }
            probe.wrapped = created.groundTiles
            server.register(routeId: groundRoute, provider: probe)
            server.register(routeId: labelRoute, provider: created.labelTiles)

            diagnostics = created.diagnostics()
            attributions = created.attributions()
            ground = RasterLayerState(
                source: .urlTemplate(
                    template: server.urlTemplate(
                        routeId: groundRoute, tileSize: tileSize, cacheKey: "static"
                    ),
                    tileSize: tileSize,
                    maxZoom: 22,
                    attributionRules: attributions.map { AttributionRule(attribution: $0) }
                ),
                zIndex: 0
            )
            labels = labelState(generation: 0)
        } catch {
            failure = "\(error)"
        }
    }

    /// Replaces the label overlay with one the map has to refetch.
    ///
    /// Only the overlay: the ground beneath it is unchanged, so the worst a
    /// handover can cost is a moment of the labels being redrawn, never a bare
    /// map.
    private func handOverLabels() {
        guard provider != nil else { return }
        generation += 1
        labels = labelState(generation: generation)
    }

    private func labelState(generation: Int) -> RasterLayerState {
        RasterLayerState(
            source: .urlTemplate(
                template: TileServerRegistry.get().urlTemplate(
                    routeId: labelRoute, tileSize: tileSize, cacheKey: "g\(generation)"
                ),
                tileSize: tileSize,
                maxZoom: 22,
                attributionRules: attributions.map { AttributionRule(attribution: $0) }
            ),
            // Above the ground.
            zIndex: 1000 + generation
        )
    }

    func dispose() {
        let server = TileServerRegistry.get()
        server.unregister(routeId: groundRoute)
        server.unregister(routeId: labelRoute)
        provider?.close()
        provider = nil
    }
}


/**
 Passes tiles through, noting which grid the backend is asking on.

 Wrapping rather than asking the SDK: what a backend requests is the only
 statement of its tile grid that is actually true, and it differs per SDK.
 */
final class TileGridProbe: TileProvider {
    var wrapped: TileProvider?
    var onObserve: ((String) -> Void)?

    private let lock = NSLock()
    private var zooms = Set<Int>()
    private var ratios = Set<Int>()

    func renderTile(request: TileRequest) -> Data? {
        // 非 throws のほうは「描けなければ空」で構わない。サーバが呼ぶのは
        // 下の isCancelled 付きのほうで、そちらは失敗を失敗のまま通す。
        try? renderTile(request: request, isCancelled: { false })
    }

    func renderTile(request: TileRequest, isCancelled: () -> Bool) throws -> Data? {
        lock.lock()
        zooms.insert(request.z)
        ratios.insert(request.pixelRatio)
        let text = "z=\(zooms.sorted().map(String.init).joined(separator: ",")) "
            + "ratio=\(ratios.sorted().map(String.init).joined(separator: ","))"
        lock.unlock()
        onObserve?(text)
        // 包むだけなので、失敗もそのまま通す（握り潰すと空タイルに化ける）。
        return try wrapped?.renderTile(request: request, isCancelled: isCancelled)
    }
}
