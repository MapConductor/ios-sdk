import Foundation
import MapConductorCore
import MapConductorVectorTile
import UIKit

/**
 The area, the package and the layer of the offline map page.

 "Select area…" enters download mode: two draggable markers mark the
 south-west and north-east corners of an area, and everything outside it is
 shaded by a polygon with the area cut out. "Download" then fetches what the
 style needs to draw that area into a package on the device, and leaves
 download mode. "Airplane mode" then cuts the layer off from the network: inside
 the area the map is drawn from the package, outside it there is nothing to
 draw -- which is how you can see the package working.
 */
@MainActor
final class OfflineMapPageViewModel: ObservableObject {
    /// Central Tokyo, an area a few kilometres across: small enough to fetch
    /// in seconds, large enough to pan around inside.
    /// `MAPCONDUCTOR_OFFLINE_CENTER` ("lat,lon") starts elsewhere, for trying other places.
    let initCameraPosition: MapCameraPosition = {
        let parts = ProcessInfo.processInfo.environment["MAPCONDUCTOR_OFFLINE_CENTER"]?
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? []
        let center = parts.count == 2
            ? GeoPoint(latitude: parts[0], longitude: parts[1])
            : GeoPoint(latitude: 35.6805, longitude: 139.7675)
        return MapCameraPosition(position: center, zoom: 13.0)
    }()

    @Published private(set) var southWest = GeoPoint(latitude: 35.6650, longitude: 139.7450)
    @Published private(set) var northEast = GeoPoint(latitude: 35.6960, longitude: 139.7900)

    /// The mask: a wide ring with the area cut out of it, so the area is the
    /// one clear patch on a darkened map. The ring follows the area -- a hole
    /// has to lie inside its ring, and one that does not is not a hole but a
    /// second, filled polygon (which is what the map drew when the ring was
    /// left over Tokyo and the area was chosen in Los Angeles).
    let mask: PolygonState
    let swMarker: MarkerState
    let neMarker: MarkerState

    @Published private(set) var offlinePackage: OfflinePackage?
    @Published private(set) var progress: OfflinePackageDownloader.Progress?
    @Published var airplane = false
    /// Download mode: the area markers and the shade are shown only while an
    /// area is being chosen. The rest of the time the page is just the map.
    @Published private(set) var selecting = false
    @Published private(set) var stats: OfflinePackage.Stats?
    @Published private(set) var failure: String?
    @Published private(set) var diagnostics: [String] = []

    // The layer, raster path: one provider, the ground and the labels.
    @Published private(set) var ground: RasterLayerState?
    @Published private(set) var labels: [RasterLayerState] = []
    @Published private(set) var isDirect = false

    private var styleJSON: String?
    private var provider: VectorTileProvider?
    private var fetcher: OfflinePackage.Fetcher?
    private var handoff: VectorStyleHandoff?
    private var generation = 0
    private let routeId = "sample-offline-\(UUID().uuidString)"
    private var mountedFor: String?

    let packageDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("offline-map")

    init() {
        let sw = GeoPoint(latitude: 35.6650, longitude: 139.7450)
        let ne = GeoPoint(latitude: 35.6960, longitude: 139.7900)
        mask = PolygonState(
            points: Self.maskRing(sw, ne),
            holes: [Self.rectangle(sw, ne)],
            id: "offline-mask",
            strokeColor: .clear,
            strokeWidth: 0,
            fillColor: UIColor.black.withAlphaComponent(0.5),
            // Above the tiles: on backends that order tile overlays and
            // shapes in one z space, a shade at 0 sits under the map.
            zIndex: 10_000
        )
        swMarker = MarkerState(
            position: sw,
            id: "sw",
            icon: DefaultMarkerIcon(fillColor: UIColor(red: 0.11, green: 0.31, blue: 0.85, alpha: 1), strokeColor: .white, label: "SW", labelTextColor: .white),
            clickable: false,
            draggable: true
        )
        neMarker = MarkerState(
            position: ne,
            id: "ne",
            icon: DefaultMarkerIcon(fillColor: UIColor(red: 0.73, green: 0.11, blue: 0.11, alpha: 1), strokeColor: .white, label: "NE", labelTextColor: .white),
            clickable: false,
            draggable: true
        )
        offlinePackage = OfflinePackage.open(packageDirectory)
        swMarker.onDrag = { [weak self] in self?.cornerMoved($0) }
        swMarker.onDragEnd = { [weak self] in self?.cornerMoved($0) }
        neMarker.onDrag = { [weak self] in self?.cornerMoved($0) }
        neMarker.onDragEnd = { [weak self] in self?.cornerMoved($0) }
    }

    /// Enters download mode with the area centred on `center`.
    func beginSelection(center: GeoPoint) {
        southWest = GeoPoint(latitude: center.latitude - 0.0155, longitude: center.longitude - 0.0225)
        northEast = GeoPoint(latitude: center.latitude + 0.0155, longitude: center.longitude + 0.0225)
        swMarker.position = southWest
        neMarker.position = northEast
        mask.points = Self.maskRing(southWest, northEast)
        mask.holes = [Self.rectangle(southWest, northEast)]
        selecting = true
    }

    func cancelSelection() {
        selecting = false
    }

    private func cornerMoved(_ dragged: MarkerState) {
        let point = GeoPoint(latitude: dragged.position.latitude, longitude: dragged.position.longitude)
        if dragged.id == "sw" { southWest = point } else { northEast = point }
        mask.points = Self.maskRing(southWest, northEast)
        mask.holes = [Self.rectangle(southWest, northEast)]
    }

    /// The shade's outer ring: several degrees around the area, wherever it
    /// is, kept inside the map's latitude and longitude range so it never wraps.
    private static func maskRing(_ a: GeoPoint, _ b: GeoPoint) -> [GeoPoint] {
        let pad = 6.0
        let south = max(min(a.latitude, b.latitude) - pad, -85)
        let north = min(max(a.latitude, b.latitude) + pad, 85)
        let west = max(min(a.longitude, b.longitude) - pad, -180)
        let east = min(max(a.longitude, b.longitude) + pad, 180)
        return [
            GeoPoint(latitude: south, longitude: west), GeoPoint(latitude: south, longitude: east),
            GeoPoint(latitude: north, longitude: east), GeoPoint(latitude: north, longitude: west),
        ]
    }

    private static func rectangle(_ a: GeoPoint, _ b: GeoPoint) -> [GeoPoint] {
        let south = min(a.latitude, b.latitude), north = max(a.latitude, b.latitude)
        let west = min(a.longitude, b.longitude), east = max(a.longitude, b.longitude)
        return [
            GeoPoint(latitude: south, longitude: west), GeoPoint(latitude: south, longitude: east),
            GeoPoint(latitude: north, longitude: east), GeoPoint(latitude: north, longitude: west),
        ]
    }

    var bounds: OfflinePackage.Bounds {
        OfflinePackage.Bounds(
            south: min(southWest.latitude, northEast.latitude),
            west: min(southWest.longitude, northEast.longitude),
            north: max(southWest.latitude, northEast.latitude),
            east: max(southWest.longitude, northEast.longitude)
        )
    }

    /// The style comes from the package when there is one -- it carries the
    /// style it was made from -- and from the network only when there is
    /// not. Opening the page with the device offline and a package on it
    /// must not need the network for anything.
    func loadStyle() async {
        guard styleJSON == nil else { return }
        if let offlinePackage {
            styleJSON = offlinePackage.styleJSON
            return
        }
        do {
            styleJSON = try await VectorTileStyleLoader.load()
        } catch {
            failure = "style could not be fetched (offline with no package?): \(error)"
        }
    }

    func download() async {
        guard let styleJSON, progress == nil else { return }
        offlinePackage = nil
        failure = nil
        do {
            let created = try await OfflinePackageDownloader.download(
                styleJSON: styleJSON,
                bounds: bounds,
                minZoom: 0,
                maxZoom: 14,
                directory: packageDirectory,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.progress = progress }
                }
            )
            offlinePackage = created
            selecting = false
        } catch {
            failure = "download failed: \(error)"
        }
        progress = nil
    }

    func clearPackage() {
        OfflinePackage.delete(packageDirectory)
        offlinePackage = nil
        stats = nil
    }

    /**
     Mounts the layer for the selected backend, the way android's
     `VectorTileLayer` does: handed over directly where the backend takes a
     style, rasterised from the package everywhere else. Called again
     whenever the backend, the package or the mode changes; every change
     rebuilds, so what the package cannot answer stays blank instead of
     lingering from a cache. That is the point of the demonstration.
     */
    func mount(direct support: VectorStyleSupport?, preferredTileSize: Int?, key: String) {
        guard let styleJSON else { return }
        guard mountedFor != key else { return }
        mountedFor = key
        unmount()
        stats = nil
        let online = !airplane
        if let support {
            isDirect = true
            let created = VectorStyleHandoff(
                styleJSON: styleJSON,
                support: support,
                offlinePackage: offlinePackage,
                online: online
            )
            handoff = created
            diagnostics = [
                offlinePackage != nil
                    ? "direct: the map reads the package itself (\(online ? "online" : "offline"))"
                    : "direct: the map draws the style itself",
            ]
            return
        }
        isDirect = false
        do {
            let tileSize = preferredTileSize ?? VectorTileProvider.defaultTileSize
            var packaged: OfflinePackage.Fetcher?
            if let offlinePackage {
                packaged = OfflinePackage.Fetcher(
                    package: offlinePackage,
                    online: online,
                    onStats: { [weak self] stats in Task { @MainActor in self?.stats = stats } }
                )
            }
            fetcher = packaged
            let created = try VectorTileProvider(
                styleJSON: styleJSON,
                tileSize: tileSize,
                fetchTile: packaged.map { fetcher in { url in try fetcher.fetch(url) } }
            )
            created.onGlyphsLoaded = { [weak self] in
                Task { @MainActor in self?.handOverLabels() }
            }
            provider = created
            let server = TileServerRegistry.get()
            server.register(routeId: "\(routeId)-ground", provider: created.groundTiles)
            server.register(routeId: "\(routeId)-labels", provider: created.labelTiles)
            let credits = created.attributions().map { AttributionRule(attribution: $0) }
            ground = RasterLayerState(
                source: .urlTemplate(
                    template: server.urlTemplate(routeId: "\(routeId)-ground", tileSize: tileSize, cacheKey: "\(key)-static"),
                    tileSize: tileSize, maxZoom: 22, attributionRules: credits
                ),
                zIndex: 0
            )
            generation = 0
            labels = [labelState(tileSize: tileSize, key: key, credits: credits)]
            diagnostics = created.diagnostics()
        } catch {
            failure = "\(error)"
        }
    }

    private func labelState(tileSize: Int, key: String, credits: [AttributionRule]) -> RasterLayerState {
        RasterLayerState(
            source: .urlTemplate(
                template: TileServerRegistry.get().urlTemplate(
                    routeId: "\(routeId)-labels", tileSize: tileSize, cacheKey: "\(key)-g\(generation)"
                ),
                tileSize: tileSize, maxZoom: 22, attributionRules: credits
            ),
            zIndex: 1000 + generation
        )
    }

    private func handOverLabels() {
        guard provider != nil, let ground else { return }
        generation += 1
        guard case .urlTemplate(_, let tileSize, _, _, let credits, _) = ground.source else { return }
        labels.append(labelState(tileSize: tileSize, key: mountedFor ?? "", credits: credits))
        let keep = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.generation == keep else { return }
            self.labels = Array(self.labels.suffix(1))
        }
    }

    func unmount() {
        mountedFor = nil
        handoff?.dispose()
        handoff = nil
        let server = TileServerRegistry.get()
        server.unregister(routeId: "\(routeId)-ground")
        server.unregister(routeId: "\(routeId)-labels")
        provider?.close()
        provider = nil
        fetcher = nil
        ground = nil
        labels = []
    }
}
