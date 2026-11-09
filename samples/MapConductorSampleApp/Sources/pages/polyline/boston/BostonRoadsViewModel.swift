import Darwin
import Foundation
import MapConductorCore
import QuartzCore
import UIKit

/// What the last tap hit: a road, or nothing (`road` nil).
struct BostonRoadTap {
    let seq: Int
    let road: BostonRoad?
    /// Where the tap landed: the closest point on the road, or the map click's point.
    let point: GeoPoint?
}

struct BostonRoadStats {
    let polylines: Int
    let vertices: Int
    let loadMs: Double
    let buildMs: Double
}

/// The states handed to the map, as one object (see `BostonPolygonList`).
final class BostonPolylineList {
    let states: [PolylineState]
    init(_ states: [PolylineState]) { self.states = states }
}

/// The overlays the stacking check adds around Downtown Crossing: polygons enough
/// to be tiled, a circle, a natively drawn (geodesic) polyline and markers.
struct BostonStackingOverlays {
    let polygons: [PolygonState]
    let circle: CircleState
    let geodesic: PolylineState
    let markers: [MarkerState]
}

/**
 Boston's roads drawn with one `Polylines` on top of the real map.

 Every road of the city (Overture transportation segments, 54,645 polylines),
 coloured, widened and stacked by class. With the default
 ``PolylineTilingOptions`` they are drawn into raster tiles; the switch turns
 tiling off (every road a native polyline) and loads again, so the time from
 the file to the last `onAdded` can be compared.

 Tapping a road highlights it and shows its class, name and length in an
 InfoBubble at the closest point on the road; tapping elsewhere closes it.
 Every tap is also printed as a `BostonRoadTap` line.

 Launch environment, so a measurement opens the same view on every provider:
 `MAPCONDUCTOR_SAMPLE_INIT_CAMERA` ("lat,lng,zoom"),
 `MAPCONDUCTOR_SAMPLE_ROADS_TILING` (0 = off), `MAPCONDUCTOR_SAMPLE_ROADS_STACKING` (1 = on),
 `MAPCONDUCTOR_SAMPLE_ROADS_CYCLE` ("maplibre,googlemaps,…[,seconds]": switch the
 provider through the list, printing the memory footprint after each).
 Same data and behaviour as the React and Android samples.
 */
@MainActor
final class BostonRoadsViewModel: ObservableObject {
    static let tapped = UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)

    let initCameraPosition: MapCameraPosition

    @Published private(set) var tiling: Bool
    @Published private(set) var stacking: Bool
    @Published private(set) var polylineList = BostonPolylineList([])
    var polylines: [PolylineState] { polylineList.states }
    @Published private(set) var stats: BostonRoadStats?
    @Published private(set) var phase: BostonLoadPhase?
    @Published private(set) var loadError: String?
    @Published private(set) var tap: BostonRoadTap?
    /// From the start of loading to the last `onAdded`, and to the first.
    @Published private(set) var allAddedMs: Double?
    @Published private(set) var firstAddedMs: Double?
    @Published private(set) var addedCount = 0
    @Published private(set) var footprintMB: Double = BostonRoadsViewModel.footprintMB()
    let stackingOverlays: BostonStackingOverlays

    var tilingOptions: PolylineTilingOptions { tiling ? .Default : .Disabled }

    private var roads: [BostonRoad] = []
    private var highlighted: (state: PolylineState, color: UIColor)?
    private var loadTask: Task<Void, Never>?
    private var started = 0.0
    private var loadMs = 0.0
    private var buildMs = 0.0
    // Which roads of this load have reached the map, from their `onAdded`.
    private var generation = 0
    private var addedIds: Set<String> = []
    private var expected = 0

    init() {
        let env = ProcessInfo.processInfo.environment
        let parts = env["MAPCONDUCTOR_SAMPLE_INIT_CAMERA"]?.split(separator: ",").compactMap { Double($0) } ?? []
        let (lat, lng, zoom) = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (42.3555, -71.0605, 15.0)
        initCameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: lat, longitude: lng), zoom: zoom, bearing: 0, tilt: 0, paddings: nil
        )
        tiling = env["MAPCONDUCTOR_SAMPLE_ROADS_TILING"] != "0"
        stacking = env["MAPCONDUCTOR_SAMPLE_ROADS_STACKING"] == "1"
        stackingOverlays = Self.makeStackingOverlays()
    }

    func start() {
        if roads.isEmpty, loadTask == nil { load() }
    }

    /// Turns tiling on or off and loads the roads again, timing the load.
    func setTiling(_ on: Bool) {
        guard on != tiling else { return }
        tiling = on
        load()
    }

    func setStacking(_ on: Bool) {
        stacking = on
    }

    func onMapClick(_ point: GeoPoint) {
        onTap(state: nil, road: nil, point: point)
    }

    func refreshFootprint() {
        footprintMB = Self.footprintMB()
    }

    private func load() {
        loadTask?.cancel()
        polylineList = BostonPolylineList([])
        stats = nil
        loadError = nil
        tap = nil
        highlighted = nil
        allAddedMs = nil
        firstAddedMs = nil
        addedCount = 0
        generation += 1
        let generation = self.generation
        addedIds = []
        expected = 0
        phase = .read(loaded: 0, total: 0)
        started = CACurrentMediaTime()
        let tiling = self.tiling
        print(String(format: "ROADS load tiling=%d t=%.3f", tiling ? 1 : 0, started))
        loadTask = Task { [weak self] in
            do {
                let roads = try await BostonRoadsLoader.load { [weak self] progress in
                    guard let self, self.generation == generation, self.phase != nil else { return }
                    self.phase = progress
                }
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.loadMs = (CACurrentMediaTime() - self.started) * 1000
                self.phase = .build
                await Task.yield()
                try? await Task.sleep(nanoseconds: 16_000_000)
                let built = CACurrentMediaTime()
                let onTap: (PolylineEvent, BostonRoad) -> Void = { [weak self] event, road in
                    MainActor.assumeIsolated {
                        self?.onTap(state: event.state, road: road, point: GeoPoint.from(position: event.clicked))
                    }
                }
                let onAdded: OnPolylineAddedHandler = { [weak self] state in
                    MainActor.assumeIsolated { self?.roadAdded(state.id, generation: generation) }
                }
                let states = await Task.detached(priority: .userInitiated) {
                    roads.map { Self.makeState($0, onTap: onTap, onAdded: onAdded) }
                }.value
                guard !Task.isCancelled, self.generation == generation else { return }
                self.buildMs = (CACurrentMediaTime() - built) * 1000
                self.roads = roads
                self.expected = states.count
                let vertices = roads.reduce(0) { $0 + $1.vertexCount }
                self.stats = BostonRoadStats(polylines: states.count, vertices: vertices, loadMs: self.loadMs, buildMs: self.buildMs)
                print(String(
                    format: "ROADS shown polylines=%d vertices=%d load=%.0fms build=%.0fms t=%.3f",
                    states.count, vertices, self.loadMs, self.buildMs, CACurrentMediaTime()
                ))
                self.phase = .draw
                self.polylineList = BostonPolylineList(states)
                self.finishDrawingIfAllAdded()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = nil
                self.loadError = error.localizedDescription
            }
            self?.loadTask = nil
        }
    }

    /// `onAdded` of the road `id`: it is on the map (natively, or in the tile
    /// layer the map has been given; the tile images may still be loading).
    private func roadAdded(_ id: String, generation: Int) {
        guard generation == self.generation, addedIds.insert(id).inserted else { return }
        addedCount = addedIds.count
        if addedIds.count == 1 {
            firstAddedMs = (CACurrentMediaTime() - started) * 1000
            print(String(format: "ROADS firstAdded ms=%.0f t=%.3f", firstAddedMs ?? 0, CACurrentMediaTime()))
        }
        finishDrawingIfAllAdded()
    }

    private func finishDrawingIfAllAdded() {
        guard phase == .draw, expected > 0, addedIds.count >= expected else { return }
        phase = nil
        allAddedMs = (CACurrentMediaTime() - started) * 1000
        refreshFootprint()
        print(String(
            format: "ROADS added count=%d tiling=%d ms=%.0f footprint=%.0fMB t=%.3f",
            addedIds.count, tiling ? 1 : 0, allAddedMs ?? 0, footprintMB, CACurrentMediaTime()
        ))
    }

    /// Moves the highlight to `state` (or clears it) and records the tap.
    private func onTap(state: PolylineState?, road: BostonRoad?, point: GeoPoint?) {
        if let previous = highlighted { previous.state.strokeColor = previous.color }
        highlighted = state.map { ($0, $0.strokeColor) }
        state?.strokeColor = Self.tapped
        let seq = (tap?.seq ?? 0) + 1
        tap = BostonRoadTap(seq: seq, road: road, point: point)
        print("BostonRoadTap seq=\(seq) id=\(road?.id ?? "") lat=\(point?.latitude ?? .nan) lng=\(point?.longitude ?? .nan)")
    }

    nonisolated private static func makeState(
        _ road: BostonRoad,
        onTap: @escaping (PolylineEvent, BostonRoad) -> Void,
        onAdded: @escaping OnPolylineAddedHandler
    ) -> PolylineState {
        let points = stride(from: 0, to: road.points.count, by: 2).map {
            GeoPoint(latitude: road.points[$0 + 1], longitude: road.points[$0]) as GeoPointProtocol
        }
        return PolylineState(
            points: points,
            id: road.id,
            strokeColor: road.road.color,
            strokeWidth: road.road.width,
            zIndex: road.road.zIndex,
            extra: road.id,
            onClick: { event in onTap(event, road) },
            onAdded: onAdded
        )
    }

    /// 50 x 50 translucent squares (enough to be tiled) over Downtown Crossing,
    /// a circle, a geodesic (so natively drawn) line and three markers on top.
    nonisolated private static func makeStackingOverlays() -> BostonStackingOverlays {
        var polygons: [PolygonState] = []
        let lat0 = 42.3500, lng0 = -71.0680, step = 0.00025, size = 0.0002
        for i in 0..<2_500 {
            let lat = lat0 + Double(i / 50) * step, lng = lng0 + Double(i % 50) * step
            polygons.append(PolygonState(
                points: [
                    GeoPoint(latitude: lat, longitude: lng),
                    GeoPoint(latitude: lat, longitude: lng + size),
                    GeoPoint(latitude: lat + size, longitude: lng + size),
                    GeoPoint(latitude: lat + size, longitude: lng),
                ],
                id: "stack-polygon-\(i)",
                strokeColor: .clear,
                strokeWidth: 0,
                fillColor: UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 0.35)
            ))
        }
        let circle = CircleState(
            center: GeoPoint(latitude: 42.3555, longitude: -71.0605),
            radiusMeters: 180,
            strokeColor: UIColor(red: 0.6, green: 0, blue: 0.6, alpha: 1),
            strokeWidth: 2,
            fillColor: UIColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 0.6),
            id: "stack-circle"
        )
        let geodesic = PolylineState(
            points: [GeoPoint(latitude: 42.3505, longitude: -71.0650), GeoPoint(latitude: 42.3605, longitude: -71.0560)],
            id: "stack-geodesic",
            strokeColor: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            strokeWidth: 6,
            geodesic: true,
            zIndex: -100
        )
        let markers = [(42.3555, -71.0605), (42.3540, -71.0620), (42.3570, -71.0590)].enumerated().map { i, p in
            MarkerState(position: GeoPoint(latitude: p.0, longitude: p.1), id: "stack-marker-\(i)")
        }
        return BostonStackingOverlays(polygons: polygons, circle: circle, geodesic: geodesic, markers: markers)
    }

    /// The process's memory footprint (what iOS counts against the app), in MB.
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
