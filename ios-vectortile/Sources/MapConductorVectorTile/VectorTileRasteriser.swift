import Foundation
import MapConductorCore
import MapConductorVectorStyle

/**
 Draws a vector style for a map that cannot read one.

 ```swift
 GoogleMapView(
     state: state,
     style: VectorStyle(
         document: .url("https://…/style.json"),
         rules: rules,
         rasteriser: VectorTileRasteriser()
     )
 )
 ```

 Google Maps, MapKit, HERE, ArcGIS, Longdo, TomTom and the rest have no
 vector renderer to hand a style to. This renders the style to PNG tiles on
 the device and mounts them as an ordinary raster layer, so the same rules
 produce the same map on a backend that has never heard of MapLibre.

 ## Why two layers

 The ground (geometry, drawn by Metal) and the labels (glyphs, drawn on the
 CPU) are separate raster layers stacked on each other: they render in
 parallel, and glyphs arriving late refresh only the transparent overlay
 rather than redrawing the map.

 android-vectortile's `VectorTileRasteriser` is the same class.
 */
public final class VectorTileRasteriser: VectorStyleRasteriser {
    private let tileSize: Int?
    private let headers: [String: String]
    private let assetCacheDirectory: URL?
    private let renderMode: VectorTileProvider.RenderMode
    private let renderScale: Int?

    /// - Parameter tileSize: nil takes the map's own preference, which is
    ///   almost always right -- a provider that wants 256 says so through
    ///   ``RasterTilePreferenceKey``.
    public init(
        tileSize: Int? = nil,
        headers: [String: String] = [:],
        assetCacheDirectory: URL? = nil,
        renderMode: VectorTileProvider.RenderMode = .auto,
        renderScale: Int? = nil
    ) {
        self.tileSize = tileSize
        self.headers = headers
        self.assetCacheDirectory = assetCacheDirectory
        self.renderMode = renderMode
        self.renderScale = renderScale
    }

    public func install(host: MapStyleHost, styleJSON: String, affects _: StyleAffects)
        -> VectorStyleRasterisation
    {
        let rasterisation = Rasterisation(host: host, options: self)
        rasterisation.start(styleJSON: styleJSON)
        return rasterisation
    }

    fileprivate final class Rasterisation: VectorStyleRasterisation {
        private let host: MapStyleHost
        private let options: VectorTileRasteriser
        private let groupId = "vectorstyle-raster-\(UUID().uuidString)"
        private let lock = NSLock()

        /// Daemon-ish and serial: a map has one style, and the work is a
        /// parse plus a re-rasterise.
        private let work = DispatchQueue(label: "mapconductor.vectorstyle.raster", qos: .userInitiated)

        private var disposed = false
        private var revision = 0
        private var pendingStyleJSON: String?
        private var redrawScheduled = false
        private var provider: VectorTileProvider?
        // Accessed on `work`; revisions and provider ownership use `lock`.
        private var displayedStyle: RasterStyleSnapshot?
        private var credits: [AttributionRule] = []
        private var resolvedTileSize = VectorTileProvider.defaultTileSize

        /**
         Bumped whenever the pixels change for the same geometry.

         A map only refetches a raster source whose URL changed, so a restyle
         has to reach the template. The ground and the labels are counted
         apart: recolouring roads need not redraw the labels, and `affects`
         is what says which moved.
         */
        private var groundGeneration = 0
        private var labelGeneration = 0

        init(host: MapStyleHost, options: VectorTileRasteriser) {
            self.host = host
            self.options = options
        }

        func start(styleJSON: String) {
            work.async { [weak self] in
                guard let self else { return }
                resolvedTileSize =
                    options.tileSize
                    ?? host.serviceRegistry.get(RasterTilePreferenceKey.self)?.preferredTileSize
                    ?? VectorTileProvider.defaultTileSize
                do {
                    try apply(styleJSON: styleJSON, revision: nil)
                } catch {
                    host.report(["the style could not be rasterised: \(describe(error))"])
                }
            }
        }

        func restyle(styleJSON: String, affects _: StyleAffects) {
            lock.lock()
            guard !disposed else { lock.unlock(); return }
            revision += 1
            pendingStyleJSON = styleJSON
            guard !redrawScheduled else { lock.unlock(); return }
            redrawScheduled = true
            lock.unlock()
            // A slider emits every frame. Coalesce a short interval into one
            // document, retaining periodic previews during a continuous drag.
            work.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
                guard let self else { return }
                lock.lock()
                let latest = pendingStyleJSON
                let requestedRevision = revision
                pendingStyleJSON = nil
                redrawScheduled = false
                lock.unlock()
                guard let latest, isCurrent(requestedRevision) else { return }
                do {
                    try apply(styleJSON: latest, revision: requestedRevision)
                } catch {
                    host.report(["the style could not be redrawn: \(describe(error))"])
                }
            }
        }

        private func isCurrent(_ requestedRevision: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !disposed && revision == requestedRevision
        }

        func dispose() {
            lock.lock()
            if disposed {
                lock.unlock()
                return
            }
            disposed = true
            pendingStyleJSON = nil
            let current = provider
            provider = nil
            lock.unlock()

            host.tileServer.unregister(routeId: "\(groupId)-geom")
            host.tileServer.unregister(routeId: "\(groupId)-labels")
            current?.closeAsync()
            DispatchQueue.main.async { [host, groupId] in
                host.removeRaster(id: "\(groupId)-geom")
                host.removeRaster(id: "\(groupId)-labels")
            }
        }

        // MARK: - Private

        private func build(styleJSON: String) throws -> VectorTileProvider {
            try VectorTileProvider(
                styleJSON: styleJSON,
                tileSize: resolvedTileSize,
                headers: options.headers,
                renderMode: options.renderMode,
                assetCacheDirectory: options.assetCacheDirectory,
                renderScale: options.renderScale
            )
        }

        private func apply(styleJSON: String, revision requestedRevision: Int?) throws {
            let snapshot = try RasterStyleSnapshot(styleJSON: styleJSON)
            let affects = displayedStyle.map { snapshot.changes(from: $0) } ?? .both
            guard affects != .none else { return }
            let created = try build(styleJSON: styleJSON)
            watchGlyphs(of: created)

            lock.lock()
            guard !disposed, requestedRevision == nil || requestedRevision == revision else {
                lock.unlock()
                created.closeAsync()
                return
            }
            let previous = provider
            if let previous { created.reuseSourceTiles(from: previous) }
            provider = created
            displayedStyle = snapshot
            // Commit routes under the ownership lock so dispose cannot
            // unregister them just before an in-flight build re-registers.
            host.tileServer.register(routeId: "\(groupId)-geom", provider: created.groundTiles)
            host.tileServer.register(routeId: "\(groupId)-labels", provider: created.labelTiles)
            credits = created.attributions().map { AttributionRule(attribution: $0) }
            if affects == .ground || affects == .both { groundGeneration += 1 }
            if affects == .labels || affects == .both { labelGeneration += 1 }
            let ground = affects == .ground || affects == .both ? groundState() : nil
            let labels = affects == .labels || affects == .both ? labelState() : nil
            lock.unlock()
            previous?.closeAsync()
            DispatchQueue.main.async { [weak self] in
                guard let self, !isDisposed() else { return }
                host.report(created.diagnostics())
                if let ground { host.upsertRaster(ground) }
                if let labels { host.upsertRaster(labels) }
            }
        }

        /// Glyphs arrive after the tiles that need them -- a range is a round
        /// trip and a low zoom wants dozens -- so tiles are drawn with what
        /// is loaded and the labels refetched once more is.
        private func watchGlyphs(of created: VectorTileProvider) {
            created.onGlyphsLoaded = { [weak self, weak created] in
                guard let self else { return }
                work.async { [weak self, weak created] in
                    guard let self, let created else { return }
                    lock.lock()
                    guard !disposed, provider === created else { lock.unlock(); return }
                    labelGeneration += 1
                    let labels = labelState()
                    lock.unlock()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !isDisposed() else { return }
                        host.upsertRaster(labels)
                    }
                }
            }
        }

        private func isDisposed() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return disposed
        }

        /// Geometry only, drawn by Metal, never invalidated by glyphs.
        private func groundState() -> RasterLayerState {
            RasterLayerState(
                source: .urlTemplate(
                    template: host.tileServer.urlTemplate(
                        routeId: "\(groupId)-geom",
                        tileSize: resolvedTileSize,
                        cacheKey: "g\(groundGeneration)"
                    ),
                    tileSize: resolvedTileSize,
                    maxZoom: Self.maxZoom,
                    attributionRules: credits
                ),
                // Under everything the app declared, and under the
                // labels. A style *is* the basemap here.
                zIndex: -2,
                id: "\(groupId)-geom"
            )
        }

        /// The transparent overlay the glyphs land on.
        private func labelState() -> RasterLayerState {
            RasterLayerState(
                source: .urlTemplate(
                    template: host.tileServer.urlTemplate(
                        routeId: "\(groupId)-labels",
                        tileSize: resolvedTileSize,
                        cacheKey: "g\(labelGeneration)"
                    ),
                    tileSize: resolvedTileSize,
                    maxZoom: Self.maxZoom,
                    // Both halves carry the credit, so hiding either one
                    // cannot silence it; the overlay ends in `distinct`.
                    attributionRules: credits
                ),
                visible: displayedStyle?.hasVisibleSymbols ?? true,
                zIndex: -1,
                id: "\(groupId)-labels"
            )
        }

        private func describe(_ error: Error) -> String {
            (error as? VectorTileError).map(String.init(describing:))
                ?? (error as NSError).localizedDescription
        }

        private static let maxZoom = 22
    }
}
